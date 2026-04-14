enum PermissionKind {
  accessibility;

  String get value {
    return switch (this) {
      PermissionKind.accessibility => 'accessibility',
    };
  }

  static PermissionKind fromValue(String value) {
    return switch (value) {
      'accessibility' => PermissionKind.accessibility,
      _ => throw ArgumentError.value(value, 'value', 'Unknown PermissionKind'),
    };
  }
}

enum PermissionState {
  granted,
  denied,
  restricted,
  provisional,
  notDetermined,
  unsupported,
  unknown;

  String get value {
    return switch (this) {
      PermissionState.granted => 'granted',
      PermissionState.denied => 'denied',
      PermissionState.restricted => 'restricted',
      PermissionState.provisional => 'provisional',
      PermissionState.notDetermined => 'notDetermined',
      PermissionState.unsupported => 'unsupported',
      PermissionState.unknown => 'unknown',
    };
  }

  static PermissionState fromValue(String value) {
    return switch (value) {
      'granted' => PermissionState.granted,
      'denied' => PermissionState.denied,
      'restricted' => PermissionState.restricted,
      'provisional' => PermissionState.provisional,
      'notDetermined' => PermissionState.notDetermined,
      'unsupported' => PermissionState.unsupported,
      'unknown' => PermissionState.unknown,
      _ => PermissionState.unknown,
    };
  }
}
