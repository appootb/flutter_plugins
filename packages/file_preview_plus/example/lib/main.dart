import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:file_preview_plus/file_preview_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _filePreviewPlusPlugin = FilePreviewPlus();
  String? _path;
  Map<String, Object?>? _info;
  Uint8List? _thumbPng;
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      platformVersion =
          await _filePreviewPlusPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
    });
  }

  Future<void> _pickAndLoad() async {
    setState(() {
      _lastError = null;
    });

    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final path = res?.files.single.path;
      if (path == null || path.isEmpty) return;

      setState(() {
        _path = path;
        _info = null;
        _thumbPng = null;
      });

      final info = await _filePreviewPlusPlugin.getFileInfo(path: path);
      final thumb = await _filePreviewPlusPlugin.getThumbnail(
        path: path,
        width: 384,
        height: 384,
      );

      if (!mounted) return;
      setState(() {
        _info = info;
        _thumbPng = thumb;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('file_preview_plus demo')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _pickAndLoad,
                icon: const Icon(Icons.upload_file),
                label: const Text('Pick a file'),
              ),
              const SizedBox(height: 12),
              if (_path != null) ...[
                const Text(
                  'File path',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                SelectableText(_path!),
                const SizedBox(height: 12),
              ],
              if (_lastError != null) ...[
                const Text(
                  'Error',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$_lastError', style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              const Text(
                'Thumbnail preview (PNG bytes)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                height: 240,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _thumbPng == null
                    ? const Text('No preview')
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_thumbPng!, fit: BoxFit.contain),
                      ),
              ),
              const SizedBox(height: 16),
              const Text(
                'File info',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    const JsonEncoder.withIndent(
                      '  ',
                    ).convert(_info ?? const {}),
                    style: const TextStyle(fontFamily: 'Menlo'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
