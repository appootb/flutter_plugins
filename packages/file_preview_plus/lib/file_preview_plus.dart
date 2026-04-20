import 'dart:typed_data';

import 'file_preview_plus_platform_interface.dart';

class FilePreviewPlus {
  Future<String?> getPlatformVersion() {
    return FilePreviewPlusPlatform.instance.getPlatformVersion();
  }

  /// Returns file metadata, augmented on Dart side with extra fields:
  ///
  /// - `extension`: file extension without dot, lowercased (e.g. "pdf")
  /// - `directory`: parent directory path
  /// - `sizeHuman`: base-1000 formatted size string (e.g. "1.2 MB")
  Future<FileInfoMap> getFileInfo({required String path}) async {
    final info = await FilePreviewPlusPlatform.instance.getFileInfo(path: path);

    final effectivePath = (info['path'] as String?)?.trim().isNotEmpty == true
        ? (info['path'] as String)
        : path;

    final size = _asInt64(info['size']);

    return <String, Object?>{
      ...info,
      'extension': _fileExtension(effectivePath),
      'directory': _parentDirectory(effectivePath),
      if (size != null) 'sizeHuman': _formatBytesBase1000(size),
    };
  }

  Future<Uint8List?> getThumbnail({
    required String path,
    int width = 256,
    int height = 256,
    int? quality,
  }) {
    return FilePreviewPlusPlatform.instance.getThumbnail(
      path: path,
      width: width,
      height: height,
      quality: quality,
    );
  }
}

String _fileExtension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final fileName = normalized.split('/').last;
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

String _parentDirectory(String path) {
  final normalized = path.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  if (idx <= 0) return '';
  return normalized.substring(0, idx);
}

int? _asInt64(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _formatBytesBase1000(int bytes) {
  if (bytes < 0) return '$bytes B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  double v = bytes.toDouble();
  var unitIndex = 0;
  while (v >= 1000.0 && unitIndex < units.length - 1) {
    v /= 1000.0;
    unitIndex++;
  }
  final s = unitIndex == 0
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(v < 10 ? 1 : 0);
  return '$s ${units[unitIndex]}';
}
