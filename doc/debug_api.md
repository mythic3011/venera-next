# Debug Diagnostics API

This fork includes a local debug diagnostics API for desktop builds and desktop
runtime sessions where diagnostics are explicitly enabled.

This is a developer/operator surface. It is intended for local debugging and
bug-packet collection, not for public exposure or remote support hosting.

## Scope

- loopback only: `127.0.0.1`
- desktop only
- app-session scoped
- random ephemeral port per run
- random per-run token
- `GET` only
- redacted output by default

Current endpoints:

- `/health`
- `/logs`
- `/diagnostics`

There is no SSE or streaming mode in this surface.

## Enablement

The diagnostics API is available when any of the following is true:

- Flutter debug mode is active
- the app is built with `APP_DEBUG_DIAGNOSTICS=true`
- the app is running on desktop and the runtime setting
  `enableDebugDiagnostics` is turned on

Code reference:

- `lib/foundation/diagnostics/diagnostics.dart`
- `lib/foundation/debug_log_exporter.dart`

## How To Start It

Desktop app flow:

1. Open `Settings`.
2. Open the `Debug` page.
3. Turn on `Enable Diagnostics API` if you are not already in a debug-enabled
   runtime.
4. In `Diagnostics Server`, press `Start`.
5. Use the copy buttons for:
   - Base URL
   - Logs URL
   - Diagnostics URL
6. Use `Open App Data Directory` to inspect the local runtime state and exported
   log snapshots.
7. Use `Export Logs` to generate the merged log export and save a copy through
   the platform file picker.

The server binds to `127.0.0.1:<random-port>`.

Example base URL:

```text
http://127.0.0.1:43127
```

Each URL includes a required token query parameter.

Example:

```text
http://127.0.0.1:43127/diagnostics?token=<token>
```

## Authentication Model

- every request requires the `token` query parameter
- missing or wrong token returns `403 Forbidden`
- unknown routes return `404 Not Found`
- non-`GET` methods return `405 Method Not Allowed`

The token is generated fresh on each server start and is cleared when the
server stops.

## Endpoints

### `GET /health`

Purpose:

- quick liveness check
- confirms server state and basic log counts

Example:

```bash
curl "http://127.0.0.1:43127/health?token=<token>"
```

Response shape:

```json
{
  "ok": true,
  "platform": "macos",
  "logCount": 12,
  "sessionLogCount": 12,
  "persistedLogCount": 3,
  "debugServer": {
    "running": true
  }
}
```

### `GET /logs`

Purpose:

- inspect recent plain logs
- inspect recent structured diagnostics alongside plain logs

Query parameters:

- `token`: required
- `level`: optional, one of `all`, `info`, `warning`, `warn`, `error`
- `limit`: optional, default `200`, clamped to `1..1000`

Example:

```bash
curl "http://127.0.0.1:43127/logs?token=<token>&level=error&limit=200"
```

Response shape:

```json
{
  "logs": [],
  "structuredLogs": [],
  "count": 0,
  "structuredCount": 0,
  "limit": 200,
  "sources": {
    "session": 0,
    "persisted": 0,
    "structured": 0
  }
}
```

Notes:

- `logs` is the legacy/plain log view
- `structuredLogs` is the structured diagnostics ring-buffer view filtered by
  minimum level
- persisted log entries may appear even after in-memory session logs are
  cleared

### `GET /diagnostics`

Purpose:

- collect a fuller bug packet
- inspect runtime diagnostics state
- inspect reader-scoped diagnostics and reader debug snapshot data when present

Example:

```bash
curl "http://127.0.0.1:43127/diagnostics?token=<token>"
```

Top-level response shape:

```json
{
  "platform": {
    "os": "macos",
    "isDesktop": true
  },
  "runtime": {
    "appVersion": "..."
  },
  "debugServer": {
    "running": true,
    "baseUrl": "http://127.0.0.1:43127"
  },
  "structuredDiagnostics": {
    "enabled": true,
    "eventCount": 42,
    "runtimeLevel": "trace",
    "channels": [
      "reader.lifecycle",
      "reader.load",
      "reader.image",
      "reader.session"
    ],
    "newestWarningsAndErrors": [],
    "ndjsonLineCount": 42
  },
  "paths": {
    "dataPath": "...",
    "cachePath": "...",
    "logFilePath": "..."
  },
  "logs": {
    "totalCount": 0,
    "sessionTotalCount": 0,
    "persistedTotalCount": 0,
    "recentErrorCount": 0,
    "persistedErrorCount": 0,
    "newestErrors": []
  },
  "readerTrace": {
    "currentReader": {},
    "events": []
  }
}
```

Additional fields may appear, including:

- `readerDebugSnapshot`
- other diagnostics-owned structured payloads

## Database Architecture

The diagnostics API can inspect the unified comics database used by Venera. Understanding the database structure helps you debug:

- **`comics`** — Unified comic identity table
- **`local_library_items`** — Import/download storage tracking
- **`comic_source_links`** — Source citation with primary link tracking
- **`reader_sessions`** — Centralized reader session management
- **`reader_tabs`** — Multi-tab reading state per session
- **`remote_match_candidates`** — Deferred remote matching for comics
- **`user_tags` / `source_tags`** — Separated user vs source metadata
- **`source_platforms` / `source_platform_aliases`** — Platform identity resolution

**Example diagnostics query:**

To inspect reader session state during debugging, look for `/diagnostics` output containing `reader_sessions` data. This helps verify multi-tab state and session ownership.

See [lib/foundation/db/unified_comics_store/schema.dart](../../lib/foundation/db/unified_comics_store/schema.dart) for full schema details.

## Reader Diagnostics Notes

`/diagnostics` is the primary surface for reader failure investigation.

Current reader-related channels include:

- `reader.lifecycle`
- `reader.load`
- `reader.image`
- `reader.decode`
- `reader.session`

The reader trace payload is designed to preserve:

- `loadMode`
- `sourceKey`
- `comicId`
- `chapterId`
- `chapterIndex`
- `page`

Canonical reader session load/save/upsert events are also emitted into the
structured diagnostics stream.

## Redaction Rules

Responses are redacted before they are returned.

The redactor strips or masks values such as:

- token
- access token
- refresh token
- password
- cookie
- authorization headers
- session/account-like fields
- URL query strings containing sensitive values

This is a debugging surface, but it should still be treated as sensitive local
runtime data.

## Operational Notes

- the server only binds to loopback IPv4, not external interfaces
- the port changes on restart
- the token changes on restart
- the API is intended to be started manually from the debug page
- the output is designed for local bug investigation, not stable public API
  compatibility

## Related Files

- `lib/foundation/debug_log_exporter.dart`
- `lib/foundation/debug_diagnostics_service.dart`
- `lib/foundation/diagnostics/diagnostics.dart`
- `lib/foundation/reader/reader_diagnostics.dart`
- `lib/pages/settings/debug.dart`
