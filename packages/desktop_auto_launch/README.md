# desktop_auto_launch

A Flutter plugin that enables your desktop applications to automatically launch at system startup on Windows, macOS, and Linux.

## Usage

```dart
import 'package:desktop_auto_launch/desktop_auto_launch.dart';

const appName = 'MyApp';

final enabled = await DesktopAutoLaunch.instance.isEnabled(appName);

await DesktopAutoLaunch.instance.setEnabled(
  true,
  app: const DesktopAutoLaunchAppConfig(appName: appName),
);
```

## Platform notes

### macOS

- Uses `ServiceManagement` with `SMAppService.mainApp` (macOS 13+).
- `setEnabled`: macOS < 13 returns `UNSUPPORTED_OS`.
- `isEnabled`: macOS < 13 returns `false`.
- Only call `register()`/`unregister()` as a result of an explicit user action (App Store compliance).

### Windows

- **Packaged (MSIX/Store)**: `StartupTask`
  - Task id convention: `taskId = "<appName>Startup"`.
  - The app's MSIX/Appx manifest must declare a matching `startupTask.taskId`.
- **Unpackaged (Win32)**: `HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run`

### Linux

- Implements XDG autostart by creating/removing:
  - `~/.config/autostart/<appName>.desktop`
- The `Exec` value is derived from `/proc/self/exe` (quoted).

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

