# native_ocr

A Flutter plugin that provides native OCR capabilities using platform-specific frameworks.

## Features

- OCR from image file path
- OCR from encoded image bytes (PNG/JPEG, etc.)
- Optional `languageCodes` (BCP-47 language tags)

## API

```dart
final ocr = NativeOcr();

final text1 = await ocr.recognizeText(
  '/path/to/image.png',
  languageCodes: ['zh-Hans', 'en-US'],
);

final bytes = await File('/path/to/image.png').readAsBytes();
final text2 = await ocr.recognizeTextFromBytes(
  bytes,
  languageCodes: ['en-US'],
);
```

## Language selection (`languageCodes`)

`languageCodes` is a list of BCP-47 language tags (e.g. `en-US`, `zh-Hans`).

Unified behavior:
- If provided and non-empty: passed to the native side.
- Otherwise: the plugin falls back to system locales; if unavailable: `en-US`.
- When multiple languages are present: English (`en-*`) is moved to the end so
  non-English languages take priority when supported.

Platform notes:
- Android currently uses ML Kit `TextRecognizerOptions.DEFAULT_OPTIONS` (Latin);
  `languageCodes` may not switch models and should be treated as a hint only.
- Linux requires Tesseract/Leptonica; if missing, OCR calls return `UNAVAILABLE`.

## Docs

See `prd.md` for implementation notes and platform details.

