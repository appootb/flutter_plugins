import Cocoa
import ApplicationServices
import FlutterMacOS

public class SystemPermissionsPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "system_permissions", binaryMessenger: registrar.messenger)
        let instance = SystemPermissionsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        case "check":
            handleCheck(call, result: result)
        case "request":
            handleRequest(call, result: result)
        case "openSystemSettings":
            handleOpenSystemSettings(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private extension SystemPermissionsPlugin {
    enum PermissionKind: String {
        case accessibility
    }

    func parseKind(_ call: FlutterMethodCall) -> PermissionKind? {
        let args = call.arguments as? [String: Any]
        let kindStr = args?["kind"] as? String
        return kindStr.flatMap(PermissionKind.init(rawValue:))
    }

    func handleCheck(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let kind = parseKind(call) else {
            result(["state": "unknown"])
            return
        }

        switch kind {
        case .accessibility:
            DispatchQueue.main.async {
                let granted = AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
                        as CFDictionary)
                result(["state": granted ? "granted" : "denied"])
            }
        }
    }

    func handleRequest(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let kind = parseKind(call) else {
            result(["state": "unknown"])
            return
        }

        switch kind {
        case .accessibility:
            DispatchQueue.main.async {
                _ = AXIsProcessTrustedWithOptions(
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        as CFDictionary)

                // The system UI is out-of-process; the trust state often updates with a delay.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let granted = AXIsProcessTrustedWithOptions(
                        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
                            as CFDictionary)
                    result(["state": granted ? "granted" : "denied"])
                }
            }
        }
    }

    func handleOpenSystemSettings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let kind = parseKind(call) else {
            result(["success": false])
            return
        }

        switch kind {
        case .accessibility:
            DispatchQueue.main.async {
                let urls: [URL] = [
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ),
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy"),
                    URL(string: "x-apple.systempreferences:com.apple.preference.security"),
                ].compactMap { $0 }

                for url in urls {
                    if NSWorkspace.shared.open(url) {
                        result(["success": true])
                        return
                    }
                }

                result(["success": false])
            }
        }
    }
}
