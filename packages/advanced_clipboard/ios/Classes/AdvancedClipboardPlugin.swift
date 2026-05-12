import Darwin
import Flutter
import UIKit
import Foundation

/// Mobile clipboard reader: only emits `text`, `html`, `url`, and `image` wire types
/// (aligned with common desktop payloads). Other representations are ignored.
public class AdvancedClipboardPlugin: NSObject, FlutterPlugin {
  private static let maxInlineImageFileBytes = 40 * 1024 * 1024
  private static let imagePathExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "tif",
  ]

  // MARK: - Mobile synthetic `sourceApp` (replace base64 with your PNG bytes)

  /// Embedded 512dp phone icon (PNG), raw base64.
  private static let mobileSourceAppIconBase64iPhone = "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"

  /// Embedded 512dp tablet icon (PNG), raw base64.
  private static let mobileSourceAppIconBase64iPad = "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"

  private static func hardwareMachineIdentifier() -> String {
    var size = 0
    sysctlbyname("hw.machine", nil, &size, nil, 0)
    var buf = [CChar](repeating: 0, count: size)
    let err = sysctlbyname("hw.machine", &buf, &size, nil, 0)
    if err != 0 { return "unknown" }
    return String(cString: buf)
  }

  /// Fixed-shape `sourceApp` for mobile: `name` iPhone/iPad from idiom, `bundleId` = `hw.machine`, `icon` from constants above.
  private static func mobileSourceAppMap() -> [String: Any] {
    let idiom = UIDevice.current.userInterfaceIdiom
    let name: String
    let iconB64: String
    switch idiom {
    case .pad:
      name = "iPad"
      iconB64 = mobileSourceAppIconBase64iPad
    default:
      name = "iPhone"
      iconB64 = mobileSourceAppIconBase64iPhone
    }
    let machine = hardwareMachineIdentifier()
    let iconValue: Any
    if !iconB64.isEmpty, let data = Data(base64Encoded: iconB64) {
      iconValue = FlutterStandardTypedData(bytes: data)
    } else {
      iconValue = NSNull()
    }
    return [
      "name": name,
      "bundleId": machine,
      "icon": iconValue,
    ]
  }

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
        "sourceApp": Self.mobileSourceAppMap(),
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

    if let imgs = pb.images {
      for im in imgs {
        if let png = im.pngData() {
          out.append(contentsOf: makePart(type: "image", raw: png, meta: ["format": "png"]))
        }
      }
    }

    if let urls = pb.urls {
      for u in urls {
        appendMobilePayload(for: u, to: &out)
      }
    }

    if let s = pb.string, let utf8 = s.data(using: .utf8) {
      if let url = URL(string: s), let sch = url.scheme?.lowercased(),
        sch == "http" || sch == "https"
      {
        out.append(contentsOf: makePart(type: "url", raw: utf8, meta: nil))
        out.append(contentsOf: makePart(type: "text", raw: utf8, meta: nil))
      } else if let u = coercedURL(from: s), u.isFileURL {
        appendMobilePayload(for: u, to: &out)
      } else {
        out.append(contentsOf: makePart(type: "text", raw: utf8, meta: nil))
      }
    }

    if let html = pb.data(forPasteboardType: "public.html"), !html.isEmpty {
      out.append(contentsOf: makePart(type: "html", raw: html, meta: nil))
    }

    return orderMobileParts(out)
  }

  private static let mobileTypeOrder = ["image", "html", "url", "text"]

  private static func orderMobileParts(_ parts: [[String: Any]]) -> [[String: Any]] {
    parts.sorted { a, b in
      let ta = (a["type"] as? String) ?? ""
      let tb = (b["type"] as? String) ?? ""
      let ia = mobileTypeOrder.firstIndex(of: ta) ?? 99
      let ib = mobileTypeOrder.firstIndex(of: tb) ?? 99
      return ia < ib
    }
  }

  private static func coercedURL(from value: Any) -> URL? {
    if let u = value as? URL { return u }
    if let ns = value as? NSURL { return ns as URL }
    if let s = value as? String {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if let u = URL(string: t) { return u }
      if t.hasPrefix("/"), FileManager.default.fileExists(atPath: t) {
        return URL(fileURLWithPath: t)
      }
      return nil
    }
    if let d = value as? Data, let s = String(data: d, encoding: .utf8) {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if let u = URL(string: t) { return u }
      if t.hasPrefix("/"), FileManager.default.fileExists(atPath: t) {
        return URL(fileURLWithPath: t)
      }
    }
    return nil
  }

  /// Maps http(s) and file URLs into `url` / `text`; tries to load small raster files as `image`.
  private static func appendMobilePayload(for url: URL, to parts: inout [[String: Any]]) {
    let sch = url.scheme?.lowercased() ?? ""
    if sch == "http" || sch == "https" {
      if let d = url.absoluteString.data(using: .utf8) {
        parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
        parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
      }
      return
    }
    if url.isFileURL {
      if let img = tryLoadImageDataFromFileURL(url) {
        parts.append(contentsOf: makePart(type: "image", raw: img.data, meta: ["format": img.format]))
        return
      }
      if let d = url.absoluteString.data(using: .utf8) {
        parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
      }
      return
    }
    if let d = url.absoluteString.data(using: .utf8) {
      parts.append(contentsOf: makePart(type: "url", raw: d, meta: nil))
    }
  }

  private struct InlineImage {
    let data: Data
    let format: String
  }

  private static func tryLoadImageDataFromFileURL(_ url: URL) -> InlineImage? {
    guard url.isFileURL else { return nil }
    let ext = url.pathExtension.lowercased()
    guard imagePathExtensions.contains(ext) else { return nil }
    guard let data = try? Data(contentsOf: url),
      !data.isEmpty,
      data.count <= maxInlineImageFileBytes
    else { return nil }

    if ext == "png" || ext == "gif" {
      return InlineImage(data: data, format: ext == "gif" ? "gif" : "png")
    }
    if let img = UIImage(data: data), let png = img.pngData() {
      return InlineImage(data: png, format: "png")
    }
    return nil
  }

  private static func extractFileURLFromDocumentManagerFPItem(_ data: Data) -> URL? {
    guard let root = propertyListRoot(from: data) else { return nil }
    return firstFileLikeURL(in: root)
  }

  private static func propertyListRoot(from data: Data) -> Any? {
    var fmt = PropertyListSerialization.PropertyListFormat.binary
    if let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: &fmt) {
      return obj
    }
    var fmtXml = PropertyListSerialization.PropertyListFormat.xml
    return try? PropertyListSerialization.propertyList(from: data, options: [], format: &fmtXml)
  }

  private static func firstFileLikeURL(in obj: Any) -> URL? {
    switch obj {
    case let s as String:
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if t.isEmpty { return nil }
      if let u = URL(string: t), u.isFileURL { return u }
      if t.hasPrefix("/"), FileManager.default.fileExists(atPath: t) {
        return URL(fileURLWithPath: t)
      }
      return nil
    case let d as [String: Any]:
      for (_, v) in d {
        if let u = firstFileLikeURL(in: v) { return u }
      }
      return nil
    case let nd as NSDictionary:
      for (_, v) in nd {
        if let u = firstFileLikeURL(in: v) { return u }
      }
      return nil
    case let a as [Any]:
      for v in a {
        if let u = firstFileLikeURL(in: v) { return u }
      }
      return nil
    case let na as NSArray:
      for v in na {
        if let u = firstFileLikeURL(in: v) { return u }
      }
      return nil
    case let nested as Data:
      if let s = String(data: nested, encoding: .utf8) {
        return firstFileLikeURL(in: s)
      }
      return nil
    default:
      return nil
    }
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

      if utiLower == "public.html" {
        if let d = value as? Data, !d.isEmpty {
          parts.append(contentsOf: makePart(type: "html", raw: d, meta: nil))
        }
        continue
      }

      if utiLower == "com.apple.documentmanager.fpitem.file" {
        if let d = value as? Data, let u = extractFileURLFromDocumentManagerFPItem(d) {
          appendMobilePayload(for: u, to: &parts)
        }
        continue
      }

      if utiLower == "public.url" || utiLower == "public.file-url" {
        if let u = coercedURL(from: value) {
          appendMobilePayload(for: u, to: &parts)
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
          } else if let u = coercedURL(from: s), u.isFileURL {
            appendMobilePayload(for: u, to: &parts)
          } else {
            parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
          }
        } else if let d = value as? Data, !d.isEmpty {
          if let u = coercedURL(from: d) {
            appendMobilePayload(for: u, to: &parts)
            if !u.isFileURL, let s = String(data: d, encoding: .utf8), let td = s.data(using: .utf8) {
              parts.append(contentsOf: makePart(type: "text", raw: td, meta: nil))
            }
          } else {
            parts.append(contentsOf: makePart(type: "text", raw: d, meta: nil))
          }
        }
        continue
      }
    }

    if parts.isEmpty {
      for (_, value) in item {
        if let d = value as? Data, !d.isEmpty, let u = coercedURL(from: d) {
          appendMobilePayload(for: u, to: &parts)
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
