import Cocoa
import FlutterMacOS
import QuickLookThumbnailing
import UniformTypeIdentifiers

public class FilePreviewPlusPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "file_preview_plus", binaryMessenger: registrar.messenger)
    let instance = FilePreviewPlusPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
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
    let fm = FileManager.default

    DispatchQueue.global(qos: .utility).async {
      var info: [String: Any?] = [
        "path": path,
        "name": url.lastPathComponent
      ]

      do {
        let attrs = try fm.attributesOfItem(atPath: path)
        if let size = attrs[.size] as? NSNumber { info["size"] = size.int64Value }
        if let m = attrs[.modificationDate] as? Date { info["modifiedMs"] = Int64(m.timeIntervalSince1970 * 1000.0) }
        if let c = attrs[.creationDate] as? Date { info["createdMs"] = Int64(c.timeIntervalSince1970 * 1000.0) }
        if let type = attrs[.type] as? FileAttributeType { info["isDirectory"] = (type == .typeDirectory) }
      } catch {
        // keep partial info
      }

      if #available(macOS 11.0, *) {
        if let utType = UTType(filenameExtension: url.pathExtension) {
          info["mimeType"] = utType.preferredMIMEType
          info["uti"] = utType.identifier
        }
      }

      DispatchQueue.main.async {
        // Flutter standard codec can't encode nil values inside a Dictionary reliably.
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
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0

    DispatchQueue.global(qos: .userInitiated).async {
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .all
      )

      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
        if let cgImage = rep?.cgImage {
          let nsImage = NSImage(cgImage: cgImage, size: size)
          if let bytes = nsImage.pngData() {
            DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
            return
          }
        }

        // Fallback to system icon
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = size
        if let bytes = icon.pngData() {
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
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

private extension NSImage {
  func pngData() -> Data? {
    guard let tiff = self.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
  }
}
