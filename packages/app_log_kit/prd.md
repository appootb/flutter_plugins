# Logging package PRD (Flutter/Dart)

This document specifies a reusable **logging package** (not app-specific) for Flutter/Dart
apps, with privacy-first defaults, structured file logs, diagnostics export, and optional
telemetry injection.

---

## Goals

- **Debuggability**: reconstruct “what happened” with timestamps, module scope, and context.
- **Low friction**: app code calls a small API (`log.info(...)`) without caring about sinks.
- **Privacy-first**: avoid sensitive data by default; redact aggressively.
- **Performance**: async IO, bounded buffers, sampling/ratelimiting; no UI jank.
- **Multi-engine friendly**: multiple Flutter engines / isolates must not corrupt each other’s logs.
- **Pluggable telemetry**: inject Crash/Analytics backends via interfaces (Firebase/Sentry/PostHog/custom).

---

## Scope

### In scope

- Structured logging API and schema (JSONL)
- Multi-sink routing (console / file / memory / telemetry)
- File rotation/retention (best-effort across platforms)
- Redaction utilities (headers/URLs/paths/body rules)
- HTTP logging helpers (http client wrapper + dio interceptor)
- Diagnostics export (zip bundle) and minimal metadata capture

### Out of scope (for this package)

- App-specific UI screens (diagnostics UI can be built on top of exposed APIs)
- Full observability suite (metrics/tracing can be separate packages or optional adapters)
- Platform-native log viewers (e.g. Windows Event Log) unless explicitly added later

---

## Core features

### 1) Levels

- `trace`, `debug`, `info`, `warn`, `error`, `fatal`

### 2) Structured events (strongly recommended)

Each log record should include:

- **ts**: ISO-8601 with ms + timezone
- **level**
- **module**: e.g. `clipboard`, `sync`, `nexus`, `db`, `ui`, `network`, `permissions`
- **msg**
- **ctx**: structured map (optional): `itemId`, `windowId`, `requestId`, `durationMs`, `count`, etc.
- **error** + **stack** (optional)

> Prefer **JSONL** (one JSON per line) for file logs so we can parse/export reliably.

#### Proposed JSONL schema (v1)

Field names are intentionally short for file size, but stable.

- **v**: schema version (int), start with `1`
- **ts**: ISO-8601 with ms + timezone (string)
- **lvl**: `trace|debug|info|warn|error|fatal` (string)
- **mod**: module/category (string)
- **msg**: message (string)
- **ctx**: structured context (object, optional)
- **err**: error summary (string, optional)
- **stk**: stack trace (string, optional; can be truncated)
- **eid**: engine id (string): `dashboard|nexus|mobile` (or `windowId`-derived)
- **sid**: session id (string, optional): per app run
- **rid**: request id / correlation id (string, optional)
- **pid**: process id (int, optional; desktop)
- **tid**: thread/isolate label (string, optional)

Recommended `ctx` keys (examples, not exhaustive):

- **durMs**: duration in milliseconds (int)
- **count**: count (int)
- **itemId**: clipboard item id (string)
- **contentHash**: sha256 or similar (string)
- **primaryType**: `image|text|url|file|mixed` (string)
- **windowId**: nexus multi-window id (string/int)
- **permKind** / **permState**: permissions flow
- **http**: nested http context (see below)

#### Example record (JSONL)

```json
{
  "v": 1,
  "ts": "2026-04-14T10:22:33.456+02:00",
  "lvl": "info",
  "mod": "http",
  "msg": "request complete",
  "eid": "dashboard",
  "sid": "b7f8...",
  "rid": "req_01J...",
  "ctx": {
    "http": {
      "method": "GET",
      "host": "api.example.com",
      "path": "/v1/items",
      "status": 200,
      "durMs": 123
    }
  }
}
```

### 3) Sinks (multi-output)

- **Console sink** (dev): readable formatting, optional colors.
- **File sink** (prod): rolling logs to disk.
- **In-memory ring buffer**: last N events for a diagnostics screen.
- **Crash/telemetry sink** (optional): forward `error/fatal` to a service (sampled).

#### Telemetry injection (interface-based)

Make crash/error aggregation pluggable via interfaces so different backends can be used
(Firebase Crashlytics, Sentry, PostHog, custom server, etc.).

Recommended split (avoid a “god interface”):

- **ErrorReporter**: reports exceptions and stack traces (crash/error aggregation)
- **EventReporter** (optional): product analytics events (e.g. PostHog)
- **MetricsReporter** (optional): counters/timers

Implementation pattern:

- default **NoOp** implementations
- optional adapters: `FirebaseCrashlyticsReporter`, `SentryReporter`, `PosthogReporter`
- **CompositeErrorReporter** for “double-write” (e.g. Crashlytics + custom)

Guidelines:

- **Core package must not depend on vendor SDKs**. Vendor integrations live in optional adapter packages.
- Telemetry sinks should receive **already-redacted** events (redaction happens in core).

### 4) File logging policy

- **Directory**: app support directory + `/logs/` (platform-appropriate app support dir)
- **Rotation**:
    - by size (e.g. 5–10 MB per file) and/or daily
    - keep N days (7–30) or cap total size (e.g. 100 MB)
- **Compression**: gzip old files
- **Writing**: single writer queue; avoid concurrent writes to same file
- **Format**:
    - JSONL for machine parsing (`{ts, level, module, msg, ctx, ...}`)
    - optionally a human-readable view in the diagnostics UI (render JSON)

### 5) Runtime control

- **Log level at runtime** (no restart): global + per-module overrides
- **Sampling / rate limiting**:
    - avoid spamming repeated errors (e.g. same key once per minute)
    - sampling for verbose modules (e.g. `network`, `db`)

### 6) Diagnostics UX (high value)

Add a “Diagnostics” panel (or support action) that can:

- show recent logs from ring buffer (search + filter by level/module)
- **export a diagnostics bundle** (`.zip`):
    - logs (all engines)
    - app version/build
    - OS version + device info
    - selected settings snapshot (non-sensitive)
    - recent fatal/error summaries
- copy a short “issue summary” string for support tickets

Export bundle should include (best-effort):

- log files (all engines)
- app version/build (if provided by host app)
- OS version + device info (if available)
- selected settings snapshot (host app supplies, already redacted)
- recent fatal/error summaries (from memory sink or telemetry sink)

---

## Privacy & security (must-have)

### Never log by default

- clipboard **raw content** (plain text / HTML / RTF / image bytes)
- auth secrets: tokens, cookies, auth headers
- user PII (email/phone) unless explicitly opt-in
- full file paths (prefer file name only or hashed path)

### Redaction guidelines

When you need to reference sensitive payloads:

- log **type + size + hash** only:
    - `contentType`, `textLength`, `bytes`, `contentHash`
- for URLs: log host + path length (or redact query params)
- for file paths: log basename + extension (or hash)

Recommended redaction helpers in package:

- `Redactor.redactHeaders(Map<String,String>)`
- `Redactor.redactUrl(Uri)`
- `Redactor.redactQueryKeys(Uri)` (keys only)
- `Redactor.redactPath(String)` (basename-only or hashed)
- `Redactor.truncate(String, maxLen)`

### User-facing toggles (optional, but useful)

- **Enable debug logging** (default OFF)
- **Include sensitive details** (avoid; if added, require explicit confirmation and auto-expire)

---

## What to log (minimum coverage)

### App lifecycle

- app start/stop, foreground/background
- window show/hide/focus (Dashboard)
- Nexus slide in/out and hide reasons (escape, blur, native hide request)

### Clipboard pipeline

- capture accepted/ignored (log reason, not content)
- dedupe/persist result (`itemId`, `primaryType`, `contentHash`)
- write-back to system clipboard (by history id)
- enrichers (e.g. OCR) start/end + duration + success/failure (no content)

### Sync & account

- login/logout, token refresh (no token values)
- sync start/end, batches, failures + retry decisions
- provider selection changes

### Permissions

- `check/request/openSettings` for major permissions (e.g. macOS Accessibility)
- record resulting `PermissionState` and flow branch (first-time vs settings-guided)

### Performance points

- slow DB queries (duration + query type)
- network requests (duration + status + endpoint identifier, no sensitive params)
- heavy tasks (OCR duration, image size)

---

## HTTP logging (http / dio injection)

Provide an opt-in way to capture HTTP request/response metadata with aggressive redaction.

### Requirements

- **Works with**:
    - `package:http` (Client wrapper)
    - `dio` (Interceptor)
- **Redaction first**:
    - never log `Authorization`, cookies, tokens
    - strip or hash query params
    - log only safe headers (or allowlist)
    - never log raw request/response bodies by default
- **Correlation**:
    - assign a `rid` per request
    - include `durMs`, status, retries

### Integration surfaces

- **`package:http`**: provide `LoggingHttpClient extends http.BaseClient` that wraps an inner client.
- **`dio`**: provide `LoggingDioInterceptor` to attach to `dio.interceptors`.

Both should:

- support allowlist/denylist for hosts/paths
- support `RedactionPolicy` (headers/query/body)
- avoid logging bodies by default; allow small-body logging only behind explicit opt-in

### Suggested `ctx.http` shape

- **method**: `GET|POST|...`
- **host**: `api.example.com`
- **path**: `/v1/items` (no query)
- **queryKeys**: `["q","page"]` (optional)
- **status**: `200`
- **durMs**: `123`
- **bytesOut** / **bytesIn**: sizes (optional)
- **retries**: `0|1|...` (optional)
- **errKind**: `timeout|dns|tls|http` (optional)

### Safe defaults (recommended)

- log at `info` for non-2xx (or `warn`), `debug` for 2xx (behind debug logging)
- sample high-volume endpoints
- truncate any string fields to avoid log bloat

---

## Multi-engine / multi-process notes

Because a host app may run multiple Flutter engines/isolate groups:

- use the **same schema** everywhere
- avoid writing to the same file concurrently
- recommended naming:
    - `<engineId>-YYYYMMDD.jsonl`
- export bundles should include logs from all engines

---

## Implementation sketch (non-binding)

- `Logger` facade + `LogEvent` model
- sinks: `ConsoleSink`, `FileSink`, `MemorySink`, `CrashSink`
- `Redactor` utilities (centralized)
- a tiny “diagnostics exporter” that zips logs + metadata

### Package shape (recommended)

If we want to ship this as a reusable package, keep the core pure-Dart and adapter
dependencies optional:

- `app_logging_kit` (core): schema, sinks, redaction, rotation, exporter, http/dio adapters
- `app_logging_kit_firebase` (optional): Crashlytics adapter
- `app_logging_kit_sentry` (optional): Sentry adapter
- `app_logging_kit_posthog` (optional): PostHog adapter (events)

> Package names are placeholders; choose names that match your org conventions.

