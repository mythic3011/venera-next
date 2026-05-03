# Log Truth And Route Observer Inventory

Date: 2026-05-03  
Scope: inventory-first only; no reader lifecycle, Navigator behavior, or route-target behavior changes.

## Task 0: Workspace checkpoint

- `git status --short` shows an already dirty tree; this slice only adds inventory docs plus diagnostic metadata fields.
- Unrelated modified files are intentionally untouched.

## Task 1: L-log-unify-1 inventory

Current truth:
- Structured diagnostics (`AppDiagnostics` / `DevDiagnosticsApi`) is the runtime diagnostic authority.
- Legacy logs (`Log`) remain compatibility/UI/export-facing surfaces.
- Existing bridge is one-way from structured warn/error to legacy (`_LegacyLogDiagnosticSink` in `lib/foundation/diagnostics/diagnostics.dart`); this is projection, not source authority.

### Legacy `Log` writers

| File | Callsite(s) | Primary category | Tags |
| --- | --- | --- | --- |
| `lib/foundation/log.dart` | `Log.info/warning/error -> addLog` | `persisted_export` | `error_report` |
| `lib/foundation/diagnostics/diagnostics.dart` | `_LegacyLogDiagnosticSink.record` writes warn/error to legacy log | `bridge_projection` | `error_report` |
| `lib/pages/settings/debug.dart` | `Log.error("Open App Data Directory", ...)` | `ui_message` | `error_report` |
| `lib/pages/settings/app.dart` | `Log.error("Import data", ...)` | `ui_message` | `source_runtime` |

### Legacy `Log` readers and export paths

| File | Callsite(s) | Primary category | Tags |
| --- | --- | --- | --- |
| `lib/pages/settings/app.dart` | reads `Log.logs`, filter + `Log.clear()` in log UI | `ui_message` | `error_report` |
| `lib/pages/settings/debug.dart` | `Log.exportToFile()`, `Log.logFilePath` display | `persisted_export` | `debug_api` |
| `lib/foundation/log_diagnostics.dart` | reads session log + persisted file via `Log.logFilePath` and parser | `bridge_projection` | `debug_api` |
| `lib/foundation/debug_diagnostics_service.dart` | uses `LogDiagnostics.diagnosticSnapshot()` for `/health`, `/logs`, `/diagnostics` payloads | `bridge_projection` | `debug_api` |

### Structured diagnostics writers/readers

| File | Callsite(s) | Primary category | Tags |
| --- | --- | --- | --- |
| `lib/foundation/diagnostics/diagnostics.dart` | `AppDiagnostics.trace/info/warn/error`, ring buffer, ndjson export | `runtime_diagnostic` | `debug_api` |
| `lib/foundation/app_page_route.dart` | route lifecycle + push host diagnostics emitters | `runtime_diagnostic` | `reader` |
| `lib/features/reader/presentation/loading.dart` | reader open boundary + route snapshot correlation | `runtime_diagnostic` | `reader` |
| `lib/foundation/debug_diagnostics_service.dart` | reads structured events via `DevDiagnosticsApi.recent/exportNdjson` | `runtime_diagnostic` | `debug_api` |
| `lib/pages/settings/debug.dart` | opens diagnostics console (`TalkerScreen`), controls diagnostics server | `ui_message` | `debug_api` |

## Task 2: R-routing-inventory-1 inventory

### Route entry inventory

| Surface | Entrypoint pattern | Observer coverage | Notes |
| --- | --- | --- | --- |
| `lib/foundation/context.dart` | `context.to`, `context.toReplacement` using nearest `Navigator.of(this)` | emits `navigator.push.host`; lifecycle depends on attached observer | Non-centralized extension point used by many pages |
| `lib/pages/main_page.dart` | `MainPage.to(...)` delegates into nested navigator context | covered by `NaviObserver` on main nested navigator | `App.mainNavigatorKey` is set here |
| `lib/components/navigation_bar.dart` | internal nested `Navigator` with `observers: [widget.observer]` | covered for this navigator role | `NaviObserver` tracks `didPush/didPop/didReplace/didRemove` |
| Dialog/menu/popup surfaces | `showMenu`, `showDialog`, popups in settings/pages | generally outside `NaviObserver` route queue | potential observer gaps by design |
| Root navigator surfaces | `App.rootNavigatorKey` / `App.rootContext` pushes | push-host diagnostics emitted, lifecycle observer usually absent | role ambiguity vs nearest/main in mixed flows |

### Observer role model recorded in this slice

- `root`: push resolved to `App.rootNavigatorKey.currentState`.
- `nearest`: push resolved to current/main navigator context (non-root, non-nested).
- `nested`: push resolved to a navigator that is neither root nor main.
- `unknown`: allowed fallback for metadata like `observerAttached` when ownership is ambiguous.

Working hypothesis retained:
- Reader route hash mismatch is more likely navigator ownership / observer coverage ambiguity than reader session authority corruption.

## Task 3: Diagnostic-only ownership markers implemented

Added metadata-only route host fields consumed by reader route snapshot:
- `navigatorHash`
- `rootNavigatorHash`
- `nearestNavigatorHash`
- `mainNavigatorHash`
- `rootNavigator`
- `observerAttached` (`true`/`false`/`unknown`)
- `nestedNavigator`
- `navigatorRole` (`root`/`nearest`/`nested`)

No route target changes were made:
- no `context.to` semantic change
- no `Navigator.of(..., rootNavigator: ...)` behavior change
- no route centralization

## Task 4: Projection rule

Boundary rule for future adapter lane:
- One runtime event -> one structured diagnostic source record -> optional legacy log/message projection.

Explicitly rejected:
- split-truth writes where legacy and structured surfaces are authored independently with divergent payloads.

Allowed current state:
- legacy `Log` remains UI/debug/export-facing compatibility surface while structured diagnostics stays source authority.
