import Cocoa
import FlutterMacOS

public class AdvancedClipboardPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    // Channels
    private var methodChannel: FlutterMethodChannel!
    private var eventChannel: FlutterEventChannel!

    // Event sink to Dart
    private var eventSink: FlutterEventSink?

    // Clipboard polling
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.25 // Poll interval (seconds)
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    // App tracking
    private var lastNonSelfApp: NSRunningApplication?
    private let selfBundleId = Bundle.main.bundleIdentifier

    // Ignore flags for writes we initiated
    private var ignoreNextChange = false

    // MARK: - Plugin registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AdvancedClipboardPlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "advanced_clipboard", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)

        instance.eventChannel = FlutterEventChannel(
            name: "advanced_clipboard_events", binaryMessenger: registrar.messenger)
        instance.eventChannel.setStreamHandler(instance)

        // Listen for application activation notifications to track last non-self app
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                // If activated app is not this plugin's app, record it
                if app.bundleIdentifier != instance.selfBundleId {
                    instance.lastNonSelfApp = app
                }
            }
        }
    }

    // MARK: - MethodChannel handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "startListening":
            startMonitoring()
            result(nil)
        case "stopListening":
            stopMonitoring()
            result(nil)
        case "write":
            if let args = call.arguments as? [String: Any],
               let contents = args["contents"] as? [[String: Any]] {
                let success = writeToPasteboard(contents: contents)
                result(success)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - StreamHandler

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        self.eventSink = events
        startMonitoring()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopMonitoring()
        self.eventSink = nil
        return nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Avoid multiple timers
            self.stopMonitoring()

            // Initialize lastChangeCount to current
            self.lastChangeCount = self.pasteboard.changeCount

            // Schedule timer on main runloop
            self.timer = Timer.scheduledTimer(
                timeInterval: self.pollInterval,
                target: self,
                selector: #selector(self.timerFired),
                userInfo: nil,
                repeats: true)
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    private func stopMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            self.timer = nil
        }
    }

    @objc private func timerFired() {
        checkPasteboardChange()
    }

    private func checkPasteboardChange() {
        // Use changeCount as authoritative signal of change
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // If we intentionally wrote to pasteboard, ignore this next change
        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        // Compose entry and send to Dart
        // Note: timerFired is already called on main thread
        let entry = createClipboardEntry(changeCount: current)
        eventSink?(entry)
    }

    // MARK: - Create entry

    private func createClipboardEntry(changeCount: Int) -> [String: Any] {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let source = serializeApp(app: lastNonSelfApp ?? NSWorkspace.shared.frontmostApplication)
        let contents = extractContents(from: pasteboard)

        return [
            "timestamp": timestamp,
            "sourceApp": source,
            "contents": contents,
            "uniqueIdentifier": String(changeCount),
        ]
    }

    // MARK: - Extract contents

    private func extractContents(from pb: NSPasteboard) -> [[String: Any]] {
        var results: [[String: Any]] = []

        guard let items = pb.pasteboardItems, !items.isEmpty else {
            return results
        }

        // We iterate items; many apps provide a single item with multiple representations.
        for item in items {
            results.append(contentsOf: extractContents(from: item))
        }

        return results
    }

    private func extractContents(from item: NSPasteboardItem) -> [[String: Any]] {
        var parts: [[String: Any]] = []

        // Helper to add a part
        func addPart(
            type: String,
            raw: Data,
            metadata: [String: Any]? = nil
        ) {
            var map: [String: Any] = ["type": type, "raw": FlutterStandardTypedData(bytes: raw)]
            if let m = metadata {
                map["metadata"] = m
            }
            parts.append(map)
        }

        // Image: prefer explicit PNG, then TIFF, then try general NSImage creator
        if let pngData = item.data(forType: .png) {
            addPart(type: "image", raw: pngData, metadata: ["format": "png"])
        } else if let tiffData = item.data(forType: .tiff) {
            // Convert tiff to png bytes
            if let bitmap = NSBitmapImageRep(data: tiffData),
               let png = bitmap.representation(using: .png, properties: [:])
            {
                addPart(type: "image", raw: png, metadata: ["format": "png"])
            } else {
                // Fallback: return raw tiff
                addPart(type: "image", raw: tiffData, metadata: ["format": "tiff"])
            }
        }

        // URL (web url) - note: use .URL (public.url)
        if let urlString = item.string(forType: .URL), let urlData = urlString.data(using: .utf8) {
            addPart(type: "url", raw: urlData)
        }

        // File URL(s)
        if let fileString = item.string(forType: .fileURL) {
            // fileURL string may be percent-encoded; attempt to create URL
            if let fileURL = URL(string: fileString),
               let pathData = fileURL.path.data(using: .utf8) {
                // Check if it's a directory or file
                var metadata: [String: Any]?
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                    metadata = ["isDirectory": isDirectory.boolValue]
                }
                addPart(type: "fileUrl", raw: pathData, metadata: metadata)
            } else if let pathData = fileString.data(using: .utf8) {
                // Fallback: use raw string if URL parsing fails
                addPart(type: "fileUrl", raw: pathData)
            }
        }

        // HTML - preserve raw bytes
        if let htmlData = item.data(forType: .html) {
            addPart(type: "html", raw: htmlData)
        }

        // RTF - preserve raw bytes
        if let rtfData = item.data(forType: .rtf) {
            addPart(type: "rtf", raw: rtfData)
        }

        // Plain text (last fallback). Use public.utf8-plain-text
        // Also check if it's a valid URL
        if let text = item.string(forType: .string), let textData = text.data(using: .utf8) {
            // Check if the text is a valid URL
            if let url = URL(string: text), url.scheme != nil, (url.scheme == "http" || url.scheme == "https") {
                // It's a valid HTTP/HTTPS URL, add as both url and text
                addPart(type: "url", raw: textData)
                addPart(type: "text", raw: textData)
            } else {
                // Regular text
                addPart(type: "text", raw: textData)
            }
        }

        // If nothing got added (rare), try to iterate available types and include them as raw
        if parts.isEmpty {
            for type in item.types {
                if let raw = item.data(forType: type) {
                    // Use String(describing:) for compatibility with older SDKs
                    let typeName = String(describing: type)
                    addPart(type: typeName, raw: raw)
                }
            }
        }

        return parts
    }

    // MARK: - Utilities

    private func serializeApp(app: NSRunningApplication?) -> [String: Any?] {
        guard let app = app else {
            return ["name": nil, "bundleId": nil, "icon": nil]
        }

        let iconData: Data? = {
            guard let ic = app.icon,
           let tiff = ic.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                return nil
        }
            return png
        }()

        return [
            "name": app.localizedName,
            "bundleId": app.bundleIdentifier,
            // Use FlutterStandardTypedData for binary data
            "icon": iconData.map { FlutterStandardTypedData(bytes: $0) },
        ]
    }

    // MARK: - Write to pasteboard

    private func writeToPasteboard(contents: [[String: Any]]) -> Bool {
        pasteboard.clearContents()
        
        // Set flag to ignore the change we're about to make
        ignoreNextChange = true
        
        var success = false
        let item = NSPasteboardItem()
        var fileURLs: [URL] = []
        
        // First pass: collect file URLs and handle other types
        for content in contents {
            guard let type = content["type"] as? String else { continue }
            
            // Get raw data
            var rawData: Data?
            if let raw = content["raw"] as? FlutterStandardTypedData {
                rawData = raw.data
            } else if let rawList = content["raw"] as? [Int] {
                rawData = Data(rawList.map { UInt8($0) })
            }
            
            switch type {
            case "text":
                if let data = rawData,
                   let text = String(data: data, encoding: .utf8) {
                    item.setString(text, forType: .string)
                    success = true
                }
            case "html":
                if let data = rawData {
                    item.setData(data, forType: .html)
                    success = true
                }
            case "rtf":
                if let data = rawData {
                    item.setData(data, forType: .rtf)
                    success = true
                }
            case "url":
                if let data = rawData,
                   let urlString = String(data: data, encoding: .utf8) {
                    item.setString(urlString, forType: .URL)
                    success = true
                }
            case "fileUrl":
                if let data = rawData,
                   let pathString = String(data: data, encoding: .utf8) {
                    // Convert path to file:// URL and collect for batch write
                    let fileURL = URL(fileURLWithPath: pathString)
                    fileURLs.append(fileURL)
                    success = true
                }
            case "image":
                if let data = rawData {
                    // Try PNG first
                    if let image = NSImage(data: data) {
                        // Convert to PNG if needed
                        if let tiff = image.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let png = rep.representation(using: .png, properties: [:]) {
                            item.setData(png, forType: .png)
                            success = true
                        } else {
                            // Fallback to TIFF
                            item.setData(data, forType: .tiff)
                            success = true
                        }
                    } else {
                        // Assume it's already PNG
                        item.setData(data, forType: .png)
                        success = true
                    }
                }
            default:
                break
            }
        }
        
        // Write content to pasteboard
        var objectsToWrite: [NSPasteboardWriting] = []
        
        // Add file URLs if any (supports multiple files)
        // URL conforms to NSPasteboardWriting, so we can cast them
        if !fileURLs.isEmpty {
            objectsToWrite.append(contentsOf: fileURLs.map { $0 as NSPasteboardWriting })
        }
        
        // Add other content types if any
        if success && !fileURLs.isEmpty {
            // If we have file URLs, check if item has other content
            let hasOtherContent = item.types.contains { type in
                type != .fileURL
            }
            if hasOtherContent {
                objectsToWrite.append(item)
            }
        } else if success {
            // No file URLs, just write the item
            objectsToWrite.append(item)
        }
        
        if !objectsToWrite.isEmpty {
            pasteboard.writeObjects(objectsToWrite)
        }
        
        return success || !fileURLs.isEmpty
    }
}
