# desktop_auto_launch_example

Demonstrates how to use the desktop_auto_launch plugin.

This example demonstrates toggling **auto-launch at login** on desktop platforms.

## Run

```sh
cd packages/desktop_auto_launch/example
flutter run -d macos
# or: flutter run -d windows
# or: flutter run -d linux
```

## Notes

- The example uses a fixed `appName` to create/check the autostart entry.
- On macOS, enabling auto-start requires **macOS 13+**; older versions will return `UNSUPPORTED_OS`.

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
