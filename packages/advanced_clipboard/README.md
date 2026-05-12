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

## Desktop payload mapping (`ClipboardContentType`)

Wire values are defined in [`ClipboardContentType`](lib/src/clipboard_content_type.dart)
(`text`, `html`, `rtf`, `url`, `image`, `fileUrl`, `unknown`, `mixed`). Native code
emits the `type` string on each [`ClipboardContent`](lib/src/clipboard_content.dart)
part; Dart maps unknown strings to `ClipboardContentType.unknown`.

The table below describes what **Linux, macOS, and Windows** implementations read
today (not what every app might place on the clipboard).

| Wire `type` | macOS | Windows | Linux (GTK) |
|-------------|-------|---------|----------------|
| `text` | `NSPasteboard` plain string | `CF_UNICODETEXT` | `gtk_clipboard_wait_for_text` |
| `html` | `public.html` | `HTML Format` / `CF_HTML` (header stripped for Dart) | `text/html` |
| `rtf` | `public.rtf` | `Rich Text Format` / `CF_RTF` | **Not read** |
| `url` | `public.url`; also duplicated with `text` for `http`/`https` plain strings | `IsValidUrl(text)` (typically `http`/`https`), duplicated with `text` | Only when plain `text` starts with `http://` or `https://` |
| `image` | PNG and TIFF (TIFF often converted to PNG bytes) | `CF_BITMAP` only, converted to PNG | `gtk_clipboard_wait_for_image`, saved as PNG |
| `fileUrl` | `public.file-url` (path bytes + optional `isDirectory`) | `CF_HDROP` (one part per path) | `text/uri-list` (one part per file path; may synthesize `text`) |
| `unknown` | If nothing mapped: raw pasteboard type strings as `type` | Rarely from this path | Rarely from this path |
| `mixed` | **Never emitted** by native (reserved enum value) | Same | Same |

## Desktop coverage gaps (vs. common clipboard data)

These are **limitations of the current native extractors**, not missing Dart
types. Improving them would be incremental native work per OS.

### Windows

- **Images:** Only **`CF_BITMAP`** is read. Many apps expose **`CF_DIB` /
  `CF_DIBV5`** without a bitmap handle; those clips currently produce **no**
  `image` payload. The write path may set `CF_DIB` for compatibility, but read
  does not consume it yet.
- **Other bitmap / vector formats** (e.g. registered `PNG`, metafile formats) are
  not handled.
- **Legacy text:** Only **`CF_UNICODETEXT`**; very old sources that only set
  `CF_TEXT` / `CF_OEMTEXT` may be missed.
- **Files:** Only **`CF_HDROP`**. A `file:///…` URL that appears **only** as plain
  text (no drop list) is surfaced as **`text`**, not `fileUrl`.

### macOS

- **Images:** Only **PNG** and **TIFF** are explicitly handled. Common types such
  as **`public.jpeg`**, **HEIC**, or **WebP** may not become `image` unless they
  fall through the generic “raw UTI as `type`” path (Dart **`unknown`**).
- **RTFD** and other composite Apple types are not unpacked into `rtf` / `html`.

### Linux (GTK)

- **RTF:** There is **no** read of `text/rtf`, `application/rtf`, or similar
  targets—unlike Windows and macOS.
- **URLs:** Only **`http://` / `https://`** prefixes on the plain-text target get
  a duplicate `url` part; schemes like `mailto:` or `file://` in text alone are
  not normalized the same way as on macOS.
- **Images:** Relies on **`gtk_clipboard_wait_for_image`**. Raw **`image/png`**
  (or other) bytes without a GdkPixbuf-friendly representation may be missed
  compared to macOS/Windows.

If you rely on a format listed above, validate on target OS or extend the
native `ExtractContents` / pasteboard logic for that platform.

## Mobile clipboard models (iOS and Android)

Mobile clipboards are **a different problem domain** from desktop (macOS /
Windows / Linux): more **sandboxing**, more **vendor-specific payloads**, and
fewer stable “read this one format and you are done” contracts.

### Mobile wire types emitted by this package

On **iOS** and **Android**, `readCurrent()` / `snapshot()` only produce
`ClipboardContent` parts whose wire `type` is one of:

| Wire `type` | Meaning |
|-------------|---------|
| `text` | Plain UTF-8 text from the clip. |
| `html` | HTML / “rich text as HTML” when the platform exposes it (e.g. `public.html` on iOS, `ClipData` HTML on Android). |
| `url` | A URL string as UTF-8 bytes—**including** `http`/`https` and **`file://`** when a file reference cannot be turned into an inline `image`. |
| `image` | Raster bytes (PNG where possible, or original image bytes with a `format` hint in `metadata`). |

Everything else is **ignored** (no `fileUrl`, no `rtf`, no raw vendor UTI as
`unknown`). That keeps mobile aligned with the **most common desktop-facing**
payloads your app already handles, at the cost of dropping desktop-only shapes
such as `fileUrl` path lists on these platforms.

**File-like clips:** the native layer tries, in order: if the reference points
to a **small on-disk image** (size-capped), read it and emit **`image`**;
otherwise emit the location as **`url`** (`file://…` or `content://…` string).
Proprietary blobs (e.g. undocumented iWork packages) are skipped.

### iOS and Android vs desktop (mental model)

| Aspect | iOS (UIKit) | Android |
|--------|-------------|---------|
| Core API | [`UIPasteboard`](https://developer.apple.com/documentation/uikit/uipasteboard) (typically `.general`) | [`ClipboardManager`](https://developer.android.com/reference/android/content/ClipboardManager) + [`ClipData`](https://developer.android.com/reference/android/content/ClipData) |
| Primary structure | **Multiple items**; each item is a dictionary of **UTI string → value** (`String`, `Data`, `URL`, `UIImage`, …) | One **primary clip**; **`ClipData`** holds **`ClipData.Item`** entries (text, `Uri`, intent, HTML, …) |
| Files | **`public.file-url`**, **`UIPasteboard.urls`**, File Provider plists (`com.apple.DocumentManager.FPItem.File`) — mapped to **`url`** or **`image`**, not `fileUrl`. | **`file://`** and **`content://`** — `image/*` becomes **`image`**; other schemes become a **`url`** UTF-8 string. |
| Images | `Data` / `UIImage` under image UTIs; also **`UIPasteboard.images`** as a convenience | `contentResolver.openInputStream(uri)` for `image/*` URIs; not always a decoded bitmap in RAM |
| “What did the user copy?” | Same user action may populate **many UTIs at once** (file reference + preview bitmap + plain text body). | Same: multiple MIME / items / URI + `CharSequence` text. |
| Source app identity | **No stable public API** equivalent to desktop “foreground app that wrote the clip”; system UI may show a source label, but third-party readers generally **cannot** rely on that metadata. | Same: **`ClipDescription`** exposes labels/MIME/timestamps, not a guaranteed “writer package” for arbitrary clips. |

### iOS (`UIPasteboard`) — details

- **Items vs convenience accessors**  
  - **`items`** — array of dictionaries: keys are **uniform type identifiers** (UTIs). This is the most faithful view of “everything on the clip.”  
  - **`string`**, **`urls`**, **`images`** — synthesized views. For example, copying a file from **Files** may still populate **`urls`** with `file://` even when some UTIs are opaque; **`images`** may hold a **bitmap preview** even when the user’s intent is “a file,” not “pixels only.”  
  A robust reader often **merges** `items` with `urls` / `images` / type-specific `data(forPasteboardType:)` rather than trusting a single field.

- **Common standard-like UTIs** (non-exhaustive)  
  Plain text: `public.utf8-plain-text`, `public.plain-text`, `public.text`.  
  Web URL: `public.url`.  
  File URL / path string: `public.file-url`.  
  HTML: `public.html` as `Data`.  
  Raster: `public.png`, `public.jpeg`, `public.tiff`, etc.  
  **RTF** and other vendor-only types are **not** emitted on mobile.

- **Vendor / private UTIs**  
  When a **`file://`** URL can be recovered (e.g. from a File Provider plist), this package maps it to **`url`** or **`image`** as described above; otherwise the payload is **skipped** (not surfaced as `unknown`).

- **Change detection**  
  **`changeCount`** increments when the pasteboard changes; useful for snapshot identifiers and dedupe hints (not a cryptographic content hash).

- **Privacy**  
  Reading the general pasteboard can be subject to system policy and user-visible paste affordances on recent iOS versions; behavior may differ by context (same app vs cross-app).

### Android (`ClipboardManager` + `ClipData`) — details

- **Entry points**  
  - **`hasPrimaryClip()`** — whether there is content to read.  
  - **`getPrimaryClip()`** — returns **`ClipData?`**.

- **`ClipData` structure**  
  - **`getDescription()`** → [`ClipDescription`](https://developer.android.com/reference/android/content/ClipDescription): MIME type list, optional label, and (from API 29) a **timestamp** for the clip.  
  - **`getItemCount()` / `getItemAt(i)`** — each [`ClipData.Item`](https://developer.android.com/reference/android/content/ClipData.Item) can carry **text**, a **`Uri`**, an **Intent**, **HTML** (via the HTML APIs on `Item`), etc.—not all fields are set for every clip.

- **Files and media**  
  A “copied file” is often represented as a **`content://`** URI. Reading bytes typically goes through [`ContentResolver`](https://developer.android.com/reference/android/content/ContentResolver) (`getType`, `openInputStream`). That is **orthogonal** to a host `file://` path and must not be assumed equivalent to desktop `CF_HDROP` paths.

- **Background and OS version**  
  Clipboard access from background or across privacy boundaries is increasingly constrained (details vary by API level and OEM). In practice, **explicit reads while the app is foreground** (e.g. after resume) match common product patterns.

### Implications for this plugin and your app

1. **Mobile clips are a subset of desktop shapes** — expect at most **`text`**, **`html`**, **`url`**, and **`image`** from `readCurrent()` on iOS/Android. There is **no** `fileUrl` part on mobile; use **`url`** (`file://…`) when you need a stable file reference string.  
2. **Vendor-only payloads are dropped** — they are not emitted as Dart **`unknown`** from these mobile readers.  
3. **Do not expect `sourceApp` on mobile** — the plugin uses a placeholder; there is no cross-platform public “writer app” field comparable to desktop heuristics.  
4. **Size and persistence** — inline image reads are **size-capped**; large files or unreadable paths may only appear as a **`url`** string (or be absent). Hashing and storage policies belong in the **app**.  
5. **`readCurrent()`** is the right primitive for **explicit sync** (e.g. on resume); continuous **listening** on mobile is not implemented in native code yet.

For how this package maps native payloads to wire `type` values on each mobile
OS, see the Kotlin and Swift sources under `android/` and `ios/`.

