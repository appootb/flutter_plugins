# app_log_kit

Privacy-first structured logging toolkit for Flutter/Dart, with multi-sink support (console/file/memory/telemetry interfaces), JSONL file logs, rotation/retention, HTTP logging for `package:http` and `dio`, and diagnostics ZIP export.

## Design highlights

- **Structured**: file logs are **JSONL** (one JSON per line), easy to export and parse
- **Safe by default**: headers / url / query / path are redacted, strings are truncated to avoid log bloat
- **Low friction**: app code only calls `logger.info(...)`; sinks decide outputs
- **Multi-engine friendly**: partition logs by `engineId` (recommended: `<engineId>-YYYYMMDD.jsonl`)
- **Pluggable reporting**: inject Crash/telemetry via `ErrorReporter` (core has no vendor SDK dependencies)

## Getting started

Add the dependency in your `pubspec.yaml`:

```yaml
dependencies:
  app_log_kit:
    path: ../app_log_kit
```

Then initialize a `Logger` and configure sinks.

## Usage

### 1) Initialize a Logger (Console + Memory + File)

```dart
import 'dart:io';

import 'package:app_log_kit/app_log_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Logger> createLogger() async {
  final supportDir = await getApplicationSupportDirectory();
  final logsDir = Directory(p.join(supportDir.path, 'logs'));

  final memory = MemorySink(capacity: 500);

  final file = FileSink(
    directory: logsDir,
    engineId: 'mobile',
    maxBytesPerFile: 8 * 1024 * 1024,
    keepDays: 14,
    maxTotalBytes: 100 * 1024 * 1024,
    compressRotated: true,
  );

  final logger = Logger(
    engineId: 'mobile',
    config: LoggerConfig(
      level: LogLevel.info,
      enableDebugLogging: false, // recommended false in production
    ),
    sinks: <LogSink>[
      ConsoleSink(),
      memory,
      file,
    ],
    // Optional: inject an ErrorReporter (implemented in adapter packages for Sentry/Crashlytics/etc.)
    errorReporter: const NoopErrorReporter(),
  );

  logger.info('app', 'logger ready', ctx: <String, Object?>{'logsDir': logsDir.path});
  return logger;
}
```

### 2) Log with structured context (`ctx`)

```dart
await logger.info(
  'sync',
  'sync started',
  ctx: <String, Object?>{
    'count': 12,
    'durMs': 0,
  },
);
```

### 3) HTTP logging (`package:http`)

```dart
import 'package:http/http.dart' as http;

final client = LoggingHttpClient(
  inner: http.Client(),
  logger: logger,
  isHostAllowed: (host) => host.endsWith('example.com'),
);

final resp = await client.get(Uri.parse('https://api.example.com/v1/items?q=secret'));
```

### 4) HTTP logging (`dio`)

```dart
import 'package:dio/dio.dart';

final dio = Dio();
dio.interceptors.add(
  LoggingDioInterceptor(
    logger: logger,
    isHostAllowed: (host) => host.endsWith('example.com'),
  ),
);

final resp = await dio.get('https://api.example.com/v1/items?q=secret');
```

### 5) Export a diagnostics ZIP (support / tickets)

```dart
import 'package:path_provider/path_provider.dart';

Future<File> exportDiagnostics(Directory logsDir) async {
  final exporter = DiagnosticsExporter(logsDirectory: logsDir);
  final outDir = await getTemporaryDirectory();
  return exporter.exportZip(
    outputDirectory: outDir,
    metadataJson: <String, Object?>{
      'appVersion': '1.2.3+45',
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
    },
  );
}
```

## Security & privacy guidelines

- Do **not** log tokens / cookies / Authorization / user PII / raw content (e.g. clipboard text, image bytes)
- Prefer logging **type + size + hash** only (e.g. `bytes/textLength/contentHash`)
- If you truly need more details, gate it behind an explicit host-app toggle and auto-expire it

## Key exports

- `Logger` / `LogEvent`: structured events and facade API
- `ConsoleSink` / `FileSink` / `MemorySink`: multiple outputs (sinks)
- `Redactor` / `RedactionPolicy`: centralized redaction
- `LoggingHttpClient` / `LoggingDioInterceptor`: HTTP logging injection
- `DiagnosticsExporter`: diagnostics bundle export (zip)
