import Flutter
import UIKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

public class FilePreviewPlusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "file_preview_plus", binaryMessenger: registrar.messenger())
    let instance = FilePreviewPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "getFileInfo":
      handleGetFileInfo(call, result: result)
    case "getThumbnail":
      handleGetThumbnail(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private extension FilePreviewPlusPlugin {
  func handleGetFileInfo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty
    else {
      result(FlutterError(code: "invalid_args", message: "Missing path", details: nil))
      return
    }

    let url = URL(fileURLWithPath: path)

    DispatchQueue.global(qos: .utility).async {
      var info: [String: Any?] = [
        "path": path,
        "name": url.lastPathComponent
      ]

      do {
        let values = try url.resourceValues(forKeys: [
          .fileSizeKey,
          .contentModificationDateKey,
          .creationDateKey,
          .isDirectoryKey
        ])
        if let size = values.fileSize { info["size"] = Int64(size) }
        if let m = values.contentModificationDate { info["modifiedMs"] = Int64(m.timeIntervalSince1970 * 1000.0) }
        if let c = values.creationDate { info["createdMs"] = Int64(c.timeIntervalSince1970 * 1000.0) }
        if let isDir = values.isDirectory { info["isDirectory"] = isDir }
      } catch {
        // keep partial info
      }

      if #available(iOS 14.0, *) {
        if let utType = UTType(filenameExtension: url.pathExtension) {
          info["mimeType"] = utType.preferredMIMEType
          info["uti"] = utType.identifier
        }
      }

      DispatchQueue.main.async {
        result(info.compactMapValues { $0 })
      }
    }
  }

  func handleGetThumbnail(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty
    else {
      result(FlutterError(code: "invalid_args", message: "Missing path", details: nil))
      return
    }
    let width = (args["width"] as? NSNumber)?.doubleValue ?? 256.0
    let height = (args["height"] as? NSNumber)?.doubleValue ?? 256.0
    let size = CGSize(width: max(1.0, width), height: max(1.0, height))

    let url = URL(fileURLWithPath: path)
    let scale = UIScreen.main.scale

    DispatchQueue.global(qos: .userInitiated).async {
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .all
      )

      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
        if let uiImage = rep?.uiImage,
           let data = uiImage.pngData() {
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
          return
        }

        // Fallback: UIDocumentInteractionController icons
        let controller = UIDocumentInteractionController(url: url)
        if let icon = controller.icons.last,
           let data = icon.pngData() {
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: data)) }
          return
        }

        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "thumbnail_failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }
}
