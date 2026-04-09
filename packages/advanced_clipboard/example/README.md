# advanced_clipboard_example

Demonstrates how to use the advanced_clipboard plugin.

## Getting Started

This example focuses on **desktop clipboard change listening** (macOS/Windows/Linux).

### Run

From the plugin package directory:

```sh
cd packages/advanced_clipboard/example
flutter run -d macos
# or: flutter run -d windows
# or: flutter run -d linux
```

### What the UI shows

- **Start listening / Stop**: controls `AdvancedClipboard.instance.startListening()` and `.stopListening()`.
- **Latest entry**: the most recent `ClipboardEntry` received from the native layer:
  - `timestamp`
  - `sourceApp.name` / `sourceApp.bundleId` (best-effort, platform-specific)
  - `contents`: a list of `ClipboardContent` items (e.g. `text`, `html`, `url`, `image`, `fileUrl`).

For text-like types the example displays a UTF-8 preview; for binary types it shows the byte length.
