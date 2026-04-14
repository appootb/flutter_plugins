import Cocoa
import FlutterMacOS
import Vision

public class NativeOcrPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "native_ocr", binaryMessenger: registrar.messenger)
        let instance = NativeOcrPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "recognizeText":
            guard
                let args = call.arguments as? [String: Any],
                let imagePath = args["imagePath"] as? String
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENT", message: "Missing or invalid 'imagePath'.",
                        details: nil))
                return
            }
            let languageCodes = args["languageCodes"] as? [String]
            recognizeTextFromPath(
                imagePath, languageCodes: effectiveLanguageCodes(languageCodes), result: result)
        case "recognizeTextFromBytes":
            guard
                let args = call.arguments as? [String: Any],
                let imageBytes = args["imageBytes"] as? FlutterStandardTypedData
            else {
                result(
                    FlutterError(
                        code: "INVALID_ARGUMENT", message: "Missing or invalid 'imageBytes'.",
                        details: nil))
                return
            }
            let languageCodes = args["languageCodes"] as? [String]
            recognizeTextFromBytes(
                imageBytes.data, languageCodes: effectiveLanguageCodes(languageCodes),
                result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private func recognizeTextFromPath(
    _ path: String, languageCodes: [String], result: @escaping FlutterResult
) {
    guard let image = NSImage(contentsOfFile: path) else {
        DispatchQueue.main.async {
            result(
                FlutterError(
                    code: "INVALID_IMAGE", message: "Failed to load image from path.", details: path
                ))
        }
        return
    }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        DispatchQueue.main.async {
            result(
                FlutterError(
                    code: "INVALID_IMAGE", message: "Image has no CGImage representation.",
                    details: nil))
        }
        return
    }
    performVisionOcr(cgImage: cgImage, languageCodes: languageCodes, result: result)
}

private func recognizeTextFromBytes(
    _ bytes: Data, languageCodes: [String], result: @escaping FlutterResult
) {
    guard let image = NSImage(data: bytes) else {
        DispatchQueue.main.async {
            result(
                FlutterError(
                    code: "INVALID_IMAGE", message: "Failed to decode image bytes.", details: nil))
        }
        return
    }
    var rect = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        DispatchQueue.main.async {
            result(
                FlutterError(
                    code: "INVALID_IMAGE", message: "Image has no CGImage representation.",
                    details: nil))
        }
        return
    }
    performVisionOcr(cgImage: cgImage, languageCodes: languageCodes, result: result)
}

private func performVisionOcr(
    cgImage: CGImage, languageCodes: [String], result: @escaping FlutterResult
) {
    let request = VNRecognizeTextRequest { request, error in
        if let error = error {
            DispatchQueue.main.async {
                result(
                    FlutterError(
                        code: "OCR_ERROR", message: "Vision OCR failed.",
                        details: error.localizedDescription))
            }
            return
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            DispatchQueue.main.async {
                result("")
            }
            return
        }
        let lines: [String] = observations.compactMap { $0.topCandidates(1).first?.string }
        DispatchQueue.main.async {
            result(lines.joined(separator: "\n"))
        }
    }

    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = visionCompatibleLanguageCodes(languageCodes)

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                result(
                    FlutterError(
                        code: "OCR_ERROR", message: "Vision handler failed.",
                        details: error.localizedDescription))
            }
        }
    }
}

private func effectiveLanguageCodes(_ input: [String]?) -> [String] {
    if let input = input, !input.isEmpty {
        return reorderEnglishLast(input)
    }
    let preferred = Locale.preferredLanguages
    if !preferred.isEmpty {
        return reorderEnglishLast(preferred)
    }
    return ["en-US"]
}

private func reorderEnglishLast(_ codes: [String]) -> [String] {
    guard codes.count > 1 else { return codes }
    var nonEn: [String] = []
    var en: [String] = []
    for c in codes {
        let lower = c.lowercased()
        if lower == "en" || lower.hasPrefix("en-") {
            en.append(c)
        } else {
            nonEn.append(c)
        }
    }
    if nonEn.isEmpty { return codes }
    return nonEn + en
}

private func visionCompatibleLanguageCodes(_ codes: [String]) -> [String] {
    var out: [String] = []
    out.reserveCapacity(codes.count)
    for raw in codes {
        let code = raw.replacingOccurrences(of: "_", with: "-")
        let parts = code.split(separator: "-").map(String.init)
        if parts.count >= 2, parts[0].lowercased() == "zh" {
            out.append(parts[0] + "-" + parts[1])
            continue
        }
        if parts.count >= 2 {
            out.append(parts[0] + "-" + parts[1])
        } else {
            out.append(code)
        }
    }
    var seen = Set<String>()
    var deduped: [String] = []
    for c in out {
        let key = c.lowercased()
        if seen.insert(key).inserted {
            deduped.append(c)
        }
    }
    return deduped
}
