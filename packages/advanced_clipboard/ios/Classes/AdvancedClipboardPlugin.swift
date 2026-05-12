import Flutter
import UIKit

public class AdvancedClipboardPlugin: NSObject, FlutterPlugin {
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = AdvancedClipboardPlugin()

    let methodChannel = FlutterMethodChannel(
      name: "advanced_clipboard", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: "advanced_clipboard_events", binaryMessenger: registrar.messenger())
    eventChannel.setStreamHandler(instance)
  }

  private static func placeholderSourceApp() -> [String: Any] {
    ["name": NSNull(), "bundleId": NSNull(), "icon": NSNull()]
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "startListening":
      result(nil)
    case "stopListening":
      eventSink = nil
      result(nil)
    case "readCurrent":
      let contents = Self.extractUIPasteboardContents()
      guard !contents.isEmpty else {
        result(nil)
        return
      }
      let ts = Int64(Date().timeIntervalSince1970 * 1000)
      let snapshot: [String: Any] = [
        "timestamp": ts,
        "sourceApp": Self.placeholderSourceApp(),
        "contents": contents,
        "uniqueIdentifier": String(UIPasteboard.general.changeCount),
      ]
      result(snapshot)
    case "write":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func extractUIPasteboardContents() -> [[String: Any]] {
    let pb = UIPasteboard.general
    var out: [[String: Any]] = []

    if !pb.items.isEmpty {
      for raw in pb.items {
        guard let item = raw as? [String: Any] else { continue }
        out.append(contentsOf: contentsFromPasteboardItem(item))
      }
    }

    if !out.isEmpty {
      return out
    }

    if let imgs = pb.images {
      for im in imgs {
        if let png = im.pngData() {
          out.append(contentsOf: Self.makePart(type: "image", raw: png, meta: ["format": "png"]))
        }
      }
    }

    if let urls = pb.urls {
      for u in urls {
        if u.isFileURL {
          let path = u.path
          if let pd = path.data(using: .utf8) {
            var isDir: ObjCBool = false
            var meta: [String: Any]? = nil
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
              meta = ["isDirectory": isDir.boolValue]
            }
            out.append(contentsOf: Self.makePart(type: "fileUrl", raw: pd, meta: meta))
          }
        } else if let data = u.absoluteString.data(using: .utf8) {
          out.append(contentsOf: Self.makePart(type: "url", raw: data, meta: nil))
        }
      }
    }

    if let s = pb.string, let utf8 = s.data(using: .utf8) {
      if let url = URL(string: s), let sch = url.scheme?.lowercased(),
        sch == "http" || sch == "https"
      {
        out.append(contentsOf: Self.makePart(type: "url", raw: utf8, meta: nil))
        out.append(contentsOf: Self.makePart(type: "text", raw: utf8, meta: nil))
      } else {
        out.append(contentsOf: Self.makePart(type: "text", raw: utf8, meta: nil))
      }
    }

    if let html = pb.data(forPasteboardType: "public.html"), !html.isEmpty {
      out.append(contentsOf: Self.makePart(type: "html", raw: html, meta: nil))
    }

    if let rtf = pb.data(forPasteboardType: "public.rtf"), !rtf.isEmpty {
      out.append(contentsOf: Self.makePart(type: "rtf", raw: rtf, meta: nil))
    }

    return out
  }

  private static func contentsFromPasteboardItem(_ item: [String: Any]) -> [[String: Any]] {
    var parts: [[String: Any]] = []

    for (uti, value) in item {
      let utiLower = uti.lowercased()

      if utiLower == "public.png" || utiLower == "public.jpeg" || utiLower == "public.jpg"
        || utiLower == "public.tiff"
      {
        if let d = value as? Data {
          if utiLower == "public.tiff", let img = UIImage(data: d), let png = img.pngData() {
            parts.append(contentsOf: makePart(type: "image", raw: png, meta: ["format": "png"]))
          } else {
            let fmt: String =
              utiLower.contains("png")
              ? "png"
              : (utiLower.contains("jpeg") || utiLower.contains("jpg") ? "jpeg" : "image")
            parts.append(contentsOf: makePart(type: "image", raw: d, meta: ["format": fmt]))
          }
        }
        continue
      }

      if utiLower == "public.html", let d = value as? Data, !d.isEmpty {
        parts.append(contentsOf: makePart(type: "html", raw: d, meta: nil))
        continue
      }

      if utiLower == "public.rtf", let d = value as? Data, !d.isEmpty {
        parts.append(contentsOf: makePart(type: "rtf", raw: d, meta: nil))
        continue
      }

      if utiLower == "public.url" || utiLower == "public.file-url" {
        if let u = value as? URL {
          if u.isFileURL, let pd = u.path.data(using: .utf8) {
            var isDir: ObjCBool = false
            var meta: [String: Any]? = nil
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) {
              meta = ["isDirectory": isDir.boolValue]
            }
            parts.append(contentsOf: makePart(type: "fileUrl", raw: pd, meta: meta))
          } else if let d = u.absoluteString.data(using: .utf8) {
            parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
          }
        } else if let s = value as? String, let u = URL(string: s) {
          if u.isFileURL, let pd = u.path.data(using: .utf8) {
            parts.append(contentsOf: makePart(type: "fileUrl", raw: pd, meta: nil))
          } else if let d = s.data(using: .utf8) {
            parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
          }
        }
        continue
      }

      if utiLower == "public.utf8-plain-text" || utiLower == "public.plain-text"
        || utiLower == "public.text"
      {
        if let s = value as? String, let d = s.data(using: .utf8) {
          if let url = URL(string: s), let sch = url.scheme?.lowercased(),
            sch == "http" || sch == "https"
          {
            parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
            parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
          } else {
            parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
          }
        } else if let d = value as? Data, !d.isEmpty {
          parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
        }
        continue
      }
    }

    if parts.isEmpty {
      for (uti, value) in item {
        if let d = value as? Data, !d.isEmpty {
          parts.append(
            contentsOf: makePart(type: uti, raw: d, meta: nil))
        }
      }
    }

    return parts
  }

  private static func makePart(
    type: String,
    raw: Data,
    meta: [String: Any]?
  ) -> [[String: Any]] {
    var m: [String: Any] = [
      "type": type,
      "raw": FlutterStandardTypedData(bytes: raw),
    ]
    if let meta = meta {
      m["metadata"] = meta
    } else {
      m["metadata"] = NSNull()
    }
    return [m]
  }
}

extension AdvancedClipboardPlugin: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
