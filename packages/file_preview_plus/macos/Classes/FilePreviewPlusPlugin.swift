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
  func normalizePath(_ path: String) -> String {
    let standardized = URL(fileURLWithPath: path).standardizedFileURL
    return standardized.resolvingSymlinksInPath().path
  }

  func systemIconPng(path: String, size: CGSize) -> Data? {
    let normalized = normalizePath(path)
    let icon = NSWorkspace.shared.icon(forFile: normalized)
    return icon.pngData(size: size)
  }

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

    let normalizedPath = normalizePath(path)
    let url = URL(fileURLWithPath: normalizedPath)
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0

    DispatchQueue.global(qos: .userInitiated).async {
      // Directory: prefer returning Finder/system icon (QuickLook thumbnailing is
      // often unavailable for folders under App Sandbox without access).
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory),
         isDirectory.boolValue
      {
        if let bytes = self.systemIconPng(path: normalizedPath, size: size) {
          DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
          return
        }
      }

      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: size,
        scale: scale,
        representationTypes: .all
      )

      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
        if let cgImage = rep?.cgImage {
          let nsImage = NSImage(cgImage: cgImage, size: size)
          if let bytes = nsImage.pngData(size: size) {
            DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: bytes)) }
            return
          }
        }

        // Fallback to system icon
        if let bytes = self.systemIconPng(path: normalizedPath, size: size) {
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
  func pngData(size: CGSize) -> Data? {
    let width = Int(max(1, size.width.rounded()))
    let height = Int(max(1, size.height.rounded()))

    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }
    rep.size = size

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
    self.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.flushGraphics()

    return rep.representation(using: .png, properties: [:])
  }
}
