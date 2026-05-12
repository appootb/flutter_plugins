# advanced_clipboard

A Flutter package with advanced clipboard functionality (desktop listening,
mobile snapshot reads, structured payloads).

## One-shot snapshot vs. continuous listening

- **`AdvancedClipboard.instance.startListening` / `stopListening`**
  Subscribes to clipboard change streams on **Linux, macOS, and Windows** with
  rich payload variants (text, HTML, images, file paths, etc.), delivered as
  [`ClipboardEntry`](lib/src/clipboard_entry.dart) events.
- **`AdvancedClipboard.instance.readCurrent()`** (alias **`snapshot()`**)
  Performs a **single** native read and returns the same [`ClipboardEntry`](lib/src/clipboard_entry.dart)
  shape (or `null` if the clipboard is empty, only contains unsupported types
  after mapping, access fails, or the platform has no implementation). Supported
  on **iOS, Android**, and the same desktop targets as the listener. The stream
  handler on mobile is a no-op until native monitoring is added.

Use **readCurrent** when you control the timing—e.g. **after the app returns to
foreground** on mobile to sync with your store—without running a background
listener. Deduplication, persistence, and when to call the API stay in your app;
the plugin only maps the device clipboard into the shared model.

