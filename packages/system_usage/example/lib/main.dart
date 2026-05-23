import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_usage/src/models.dart';
import 'package:system_usage/system_usage.dart';

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
  final _systemUsagePlugin = SystemUsage();
  String _snapshot = '';
  StreamSubscription<SystemSnapshot>? _snapshotSub;

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
          await _systemUsagePlugin.getPlatformVersion() ??
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
    _snapshotSub ??= _systemUsagePlugin
        .watch(
          includes: [ResourceType.gpu],
          interval: const Duration(seconds: 1),
        )
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _snapshot = snap.gpu?.usage.toString() ?? 'n/a';
          });
        });
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(
          child: Text('Running on: $_platformVersion\n\nSnapshot: $_snapshot'),
        ),
      ),
    );
  }
}
