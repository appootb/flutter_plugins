Role: You are an expert Flutter Desktop and Mobile plugin developer.
Task: I am developing a Flutter plugin named file_preview_plus. I need you to provide the native implementation for two core methods: getFileInfo (returns metadata like name, size, mimeType) and getThumbnail (returns the preview image or system icon as a byte array/Uint8List).
Reference: The design should be inspired by flutter_file_info but extended to support Android, iOS, macOS, Windows, and Linux.
Requirements for each platform:
Android (Kotlin): Use ContentResolver.loadThumbnail for Android Q+ and MediaStore for older versions. Use PackageManager for APK icons.
iOS/macOS (Swift): Use QLThumbnailGenerator for high-quality previews of documents/videos and NSWorkspace.icon (macOS) / UIDocumentInteractionController (iOS) for icons.
Windows (C++): Use IShellItemImageFactory for thumbnails and SHGetFileInfo for system icons.
Linux (C++): Use GIO (libgio) to query thumbnail::path and standard::icon.
Implementation Details:
Use MethodChannel to communicate between Flutter and Native.
For getThumbnail, the native side should return a ByteArray (Uint8List in Flutter).
Handle IO operations on background threads to avoid UI jank.
Provide a clear Dart interface (Abstract Class) and the corresponding Native implementation for macOS.
Please output the code for the Native part of the specified platform and the Dart MethodChannel bridge.
