import Cocoa
import FlutterMacOS
import ServiceManagement

public class DesktopAutoLaunchPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "desktop_auto_launch", binaryMessenger: registrar.messenger)
    let instance = DesktopAutoLaunchPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "isEnabled":
      if #available(macOS 13.0, *) {
        result(SMAppService.mainApp.status == .enabled)
      } else {
        result(false)
      }
    case "setEnabled":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing arguments.", details: nil))
        return
      }
      guard let enabled = args["enabled"] as? Bool else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing `enabled`.", details: nil))
        return
      }
      if #available(macOS 13.0, *) {
        do {
          if enabled {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(true)
        } catch {
          result(FlutterError(code: "AUTO_START_ERROR", message: "Failed to update auto-start state.", details: "\(error)"))
        }
      } else {
        result(FlutterError(code: "UNSUPPORTED_OS", message: "Auto-start requires macOS 13.0 or newer.", details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
