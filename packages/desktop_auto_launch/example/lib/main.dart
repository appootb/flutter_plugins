import 'dart:async';

import 'package:desktop_auto_launch/desktop_auto_launch.dart';
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
  static const _appName = 'desktop_auto_launch_example';

  String _platformVersion = 'Unknown';
  bool? _enabled;
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
          await DesktopAutoLaunch.instance.getPlatformVersion() ??
              'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    bool? enabled;
    String? error;
    try {
      enabled = await DesktopAutoLaunch.instance.isEnabled(_appName);
    } on PlatformException catch (e) {
      error = '${e.code}: ${e.message ?? ''}'.trim();
    } catch (e) {
      error = e.toString();
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
      _enabled = enabled;
      _error = error;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _enabled = enabled;
      _error = null;
    });
    try {
      final ok = await DesktopAutoLaunch.instance.setEnabled(
        enabled,
        app: const DesktopAutoLaunchAppConfig(appName: _appName),
      );
      if (!ok) {
        throw PlatformException(
          code: 'AUTO_START_ERROR',
          message: 'Native side returned false.',
        );
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code}: ${e.message ?? ''}'.trim();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      // Refresh status after attempting to set.
      unawaited(initPlatformState());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('desktop_auto_launch example')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Running on: $_platformVersion'),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-launch at login'),
              subtitle: Text('appName: $_appName'),
              trailing: Switch(
                value: _enabled ?? false,
                onChanged: _enabled == null ? null : _setEnabled,
              ),
            ),
            if (_enabled == null)
              const Text('Loading status…')
            else
              Text('Enabled: $_enabled'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
