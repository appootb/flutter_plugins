import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_permissions/permission_models.dart';
import 'package:system_permissions/system_permissions_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelSystemPermissions platform = MethodChannelSystemPermissions();
  const MethodChannel channel = MethodChannel('system_permissions');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          log.add(methodCall);
          switch (methodCall.method) {
            case 'getPlatformVersion':
              return '42';
            case 'check':
              return <String, Object?>{'state': 'granted'};
            case 'request':
              return <String, Object?>{'state': 'denied'};
            case 'openSystemSettings':
              return <String, Object?>{'success': true};
          }
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    log.clear();
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('check(accessibility)', () async {
    final state = await platform.check(PermissionKind.accessibility);
    expect(state, PermissionState.granted);
    expect(log.last.method, 'check');
    expect(log.last.arguments, {'kind': 'accessibility'});
  });

  test('request(accessibility)', () async {
    final state = await platform.request(PermissionKind.accessibility);
    expect(state, PermissionState.denied);
    expect(log.last.method, 'request');
    expect(log.last.arguments, {'kind': 'accessibility'});
  });

  test('openSystemSettings(accessibility)', () async {
    final success = await platform.openSystemSettings(
      PermissionKind.accessibility,
    );
    expect(success, true);
    expect(log.last.method, 'openSystemSettings');
    expect(log.last.arguments, {'kind': 'accessibility'});
  });
}
