import 'dart:async';

import 'package:advanced_clipboard/advanced_clipboard.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _platformVersion;
  bool _isListening = false;
  ClipboardEntry? _lastEntry;
  String? _error;

  late final _listener = _UiListener((entry) {
    if (!mounted) return;
    setState(() {
      _lastEntry = entry;
      _error = null;
    });
  });

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  Future<void> initPlatformState() async {
    try {
      final v = await AdvancedClipboard.instance.getPlatformVersion();
      if (!mounted) return;
      setState(() => _platformVersion = v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _platformVersion = null);
    }
  }

  Future<void> _start() async {
    if (_isListening) return;
    try {
      AdvancedClipboard.instance.startListening(_listener);
      setState(() {
        _isListening = true;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    if (!_isListening) return;
    try {
      await AdvancedClipboard.instance.stopListening();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    // Best-effort cleanup when user closes the app.
    unawaited(AdvancedClipboard.instance.stopListening());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _lastEntry;

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('advanced_clipboard example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Platform version: ${_platformVersion ?? "unknown"}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _isListening ? null : _start,
                  child: const Text('Start listening'),
                ),
                OutlinedButton(
                  onPressed: _isListening ? _stop : null,
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatusBanner(isListening: _isListening, error: _error),
            const SizedBox(height: 12),
            Text('Latest entry', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (entry == null)
              Text(
                'No clipboard events yet. Copy something (text/url/image/file) while listening.',
                style: theme.textTheme.bodyMedium,
              )
            else
              _EntryCard(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _UiListener implements ClipboardListener {
  _UiListener(this._onChange);

  final void Function(ClipboardEntry entry) _onChange;

  @override
  void onClipboardChanged(ClipboardEntry entry) => _onChange(entry);
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.isListening, required this.error});

  final bool isListening;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = error != null
        ? theme.colorScheme.errorContainer
        : (isListening
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest);

    final fg = error != null
        ? theme.colorScheme.onErrorContainer
        : (isListening
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant);

    final text = error != null
        ? 'Error: $error'
        : (isListening ? 'Listening…' : 'Not listening');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});

  final ClipboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = entry.sourceApp;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('timestamp: ${entry.timestamp.toIso8601String()}'),
            if (entry.uniqueIdentifier != null)
              Text('uniqueIdentifier: ${entry.uniqueIdentifier}'),
            const SizedBox(height: 8),
            Text('sourceApp', style: theme.textTheme.titleSmall),
            Text('name: ${source?.name ?? "-"}'),
            Text('bundleId: ${source?.bundleId ?? "-"}'),
            const SizedBox(height: 12),
            Text(
              'contents (${entry.contents.length})',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            ...entry.contents.map((c) => _ContentTile(content: c)),
          ],
        ),
      ),
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({required this.content});

  final ClipboardContent content;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String subtitle;
    switch (content.type) {
      case ClipboardContentType.plainText:
      case ClipboardContentType.html:
      case ClipboardContentType.rtf:
      case ClipboardContentType.url:
      case ClipboardContentType.fileUrl:
        subtitle = content.content ?? '(no text)';
        break;
      case ClipboardContentType.image:
        subtitle = '${content.raw?.length ?? 0} bytes';
        break;
      case ClipboardContentType.unknown:
        subtitle = '${content.raw?.length ?? 0} bytes';
        break;
      case ClipboardContentType.mixed:
        subtitle = '${content.raw?.length ?? 0} bytes';
        break;
    }

    if (subtitle.length > 200) {
      subtitle = '${subtitle.substring(0, 200)}…';
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(content.type.value),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
    );
  }
}
