import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_permissions/permission_models.dart';
import 'package:system_permissions/system_permissions.dart';

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
  final _systemPermissionsPlugin = SystemPermissions();
  PermissionState? _accessibilityState;
  String? _error;

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
          await _systemPermissionsPlugin.getPlatformVersion() ??
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

  Future<void> _checkAccessibility() async {
    setState(() {
      _error = null;
    });
    try {
      final state = await _systemPermissionsPlugin.check(
        PermissionKind.accessibility,
      );
      if (!mounted) return;
      setState(() {
        _accessibilityState = state;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _requestAccessibility() async {
    setState(() {
      _error = null;
    });
    try {
      final state = await _systemPermissionsPlugin.request(
        PermissionKind.accessibility,
      );
      if (!mounted) return;
      setState(() {
        _accessibilityState = state;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _openAccessibilitySettings() async {
    setState(() {
      _error = null;
    });
    try {
      await _systemPermissionsPlugin.openSystemSettings(
        PermissionKind.accessibility,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Running on: $_platformVersion'),
              const SizedBox(height: 16),
              Text(
                'Accessibility state: ${_accessibilityState?.value ?? 'unknown'}',
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _checkAccessibility,
                child: const Text('Check Accessibility'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _requestAccessibility,
                child: const Text('Request Accessibility'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _openAccessibilitySettings,
                child: const Text('Open Accessibility Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
