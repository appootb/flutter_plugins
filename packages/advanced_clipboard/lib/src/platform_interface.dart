import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'clipboard_entry.dart';
import 'method_channel.dart';

/// Platform interface for `advanced_clipboard`.
///
/// Platform implementations should extend this class and set
/// [AdvancedClipboardPlatform.instance] during registration.
abstract class AdvancedClipboardPlatform extends PlatformInterface {
  /// Constructs a AdvancedClipboardPlatform.
  AdvancedClipboardPlatform() : super(token: _token);

  static final Object _token = Object();

  static AdvancedClipboardPlatform _instance = MethodChannelAdvancedClipboard();

  /// The default instance of [AdvancedClipboardPlatform] to use.
  ///
  /// Defaults to [MethodChannelAdvancedClipboard].
  static AdvancedClipboardPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [AdvancedClipboardPlatform] when
  /// they register themselves.
  static set instance(AdvancedClipboardPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the native platform version string (mainly for diagnostics).
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Start listening to clipboard changes
  ///
  /// Returns a stream of [ClipboardEntry] events emitted by the native platform.
  Stream<ClipboardEntry> startListening() {
    throw UnimplementedError('startListening() has not been implemented.');
  }

  /// Stop listening to clipboard changes
  Future<void> stopListening() {
    throw UnimplementedError('stopListening() has not been implemented.');
  }

  /// Write content to clipboard
  ///
  /// [contents] List of clipboard contents to write
  /// Returns true if successful, false otherwise
  Future<bool> write(List<Map<String, dynamic>> contents) {
    throw UnimplementedError('write() has not been implemented.');
  }
}
