import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'clipboard_entry.dart';
import 'platform_interface.dart';

/// An implementation of [AdvancedClipboardPlatform] that uses method channels.
class MethodChannelAdvancedClipboard extends AdvancedClipboardPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('advanced_clipboard');

  /// The event channel used to receive clipboard change events from native.
  @visibleForTesting
  final eventChannel = const EventChannel('advanced_clipboard_events');

  Stream<ClipboardEntry>? _clipboardStream;
  StreamSubscription<dynamic>? _subscription;

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Stream<ClipboardEntry> startListening() {
    if (_clipboardStream != null) {
      return _clipboardStream!;
    }

    _clipboardStream = eventChannel.receiveBroadcastStream().map((
      dynamic event,
    ) {
      if (event is Map) {
        return ClipboardEntry.fromMap(event);
      }
      throw Exception('Invalid clipboard event format');
    });

    // Notify native side to start listening.
    methodChannel.invokeMethod('startListening');

    return _clipboardStream!;
  }

  @override
  Future<void> stopListening() async {
    // Notify native side to stop listening.
    await methodChannel.invokeMethod('stopListening');

    // Release local stream/subscription state.
    await _subscription?.cancel();
    _subscription = null;
    _clipboardStream = null;
  }

  @override
  Future<bool> write(List<Map<String, dynamic>> contents) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('write', {
        'contents': contents,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
