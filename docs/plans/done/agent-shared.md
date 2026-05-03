# VeneraNext Reader Runtime - Agent Shared Execution Contract

Date: 2026-05-01  
Scope owner: runtime rewrite lane  
Status: active

## ADR Authority

This execution contract is governed by:
- `docs/plans/2026-05-01-stop-incremental-runtime-patching-adr.md`

If a task conflicts with that ADR, the ADR wins.

## Mission

Stop incremental patching of legacy reader runtime.  
Build a clean `VeneraNext` reader runtime kernel from scratch, using old code only as behavior reference.

## Hard Rules (Non-Negotiable)

1. No legacy reader fallback paths.
2. No adapter call may receive canonical IDs.
3. Internal app identity uses canonical IDs only.
4. External source adapters receive upstream IDs only.
5. `SourceRef` is required for every remote reader operation.
6. Missing/malformed `SourceRef` must fail closed.
7. Image cache key must include:
   - `sourceKey`
   - `canonicalComicId`
   - `upstreamComicRefId`
   - `chapterRefId`
   - `imageKey`
8. Session/history/favorites/download identity keys must be namespaced canonical IDs.
9. Old DB compatibility is importer-only, never mixed into runtime kernel.
10. UI layer must not do source resolution, adapter calls, schema migration, or cache-key construction.

## Freeze Policy for Legacy Runtime

Allowed hotfixes only:
- prevent startup crash/data loss
- diagnostics export improvements
- fail-closed disable for broken remote reader paths
- DB backup before importer/migration flows

Not allowed:
- new compatibility fallbacks
- accepting canonical IDs in adapter paths
- silent ID rewrites/normalization
- mixed large patches across reader + favorites + history + downloads

## Vertical Slice (Current Target)

Included in first slice:
- Source registry
- SourceRef + identity policy
- Remote adapter gateway
- Search
- Comic detail load
- Reader page load
- Image cache key model
- Reader resume session

Out of scope (first slice):
- favorites
- downloads
- comments
- follow updates
- account/login
- old DB migration/import
- complex gallery modes
- multi-source matching

## Current Implementation State

Runtime authority namespace is active at:
- `lib/features/reader_next/runtime/runtime.dart`
- `lib/features/reader_next/runtime/models.dart`
- `lib/features/reader_next/runtime/adapter.dart`
- `lib/features/reader_next/runtime/registry.dart`
- `lib/features/reader_next/runtime/gateway.dart`
- `lib/features/reader_next/runtime/cache_keys.dart`
- `lib/features/reader_next/runtime/session.dart`
- `lib/features/reader_next/runtime/usecases.dart`

These files are the current runtime authority for this rewrite lane.

## Updated Conclusion (2026-05-01)

Conclusion:
- Clean kernel part is no longer "implementation pending".
- Primary risk has moved to integration boundary, production cutover, and old runtime quarantine.

Execution direction:
- Do not add new kernel features in this lane.
- Open a dedicated M10 runtime cutover lane to wire ReaderNext into production paths without reintroducing legacy identity fallback.

## Layered App Breakdown

The new app must be built as separate layers. Each layer has one owner and one direction of dependency.

Dependency direction:

```text
UI -> Application Use Cases -> Runtime Domain -> Data Ports -> Infrastructure Adapters
                         \-> Diagnostics
Importer -> Data Ports
```

No layer may import from a layer to its left. Infrastructure and importer code must never call UI.

### Layer 0 - Runtime Identity Domain

Purpose:
- Own canonical identity and upstream identity types.
- Own `SourceRef` validation and fail-closed errors.
- Own cache/session/history/download key naming rules.

Allowed responsibilities:
- `CanonicalComicId`
- `SourceRef`
- `upstreamComicRefId`
- `chapterRefId`
- `sourceKey`
- typed boundary errors

Forbidden:
- adapter calls
- SQLite/Drift imports
- Flutter UI imports
- legacy DB parsing
- source plugin discovery

Owner: Agent 0 / Identity
Write scope:
- `lib/features/reader_next/runtime/models.dart`
- `lib/features/reader_next/runtime/cache_keys.dart`
- identity-only test files under `test/features/reader_next/runtime/`

### Layer 1 - Source Registry + Adapter Gateway

Purpose:
- Own source adapter registration and strict adapter dispatch.
- Convert validated `SourceRef` into adapter calls using upstream IDs only.

Allowed responsibilities:
- source registry lookup by canonical `sourceKey`
- gateway methods for search/detail/pages/image
- adapter stubs/interfaces
- fail before adapter call when boundary is invalid

Forbidden:
- accepting canonical IDs in adapter methods
- alias-tolerant runtime lookup
- fallback parser for `remote:source:id`
- UI state
- DB writes

Owner: Agent 1 / Gateway
Write scope:
- `lib/features/reader_next/runtime/adapter.dart`
- `lib/features/reader_next/runtime/registry.dart`
- `lib/features/reader_next/runtime/gateway.dart`
- gateway test files under `test/features/reader_next/runtime/`

### Layer 2 - Application Use Cases

Purpose:
- Own user flows without UI code.
- Coordinate domain, gateway, session, cache, and diagnostics.

Initial use cases:
- search
- open detail
- load reader pages
- load image bytes/cache lookup
- save/load resume session

Forbidden:
- Widget imports
- direct source plugin calls
- direct SQL
- building cache keys in UI
- legacy reader fallback

Owner: Agent 2 / Use Cases
Write scope:
- `lib/features/reader_next/runtime/usecases.dart`
- use-case tests under `test/features/reader_next/runtime/`

### Layer 3 - Runtime Data Ports

Purpose:
- Define storage interfaces used by the new runtime.
- Keep canonical DB decisions behind ports.

Ports needed in first slice:
- `ReaderSessionStore`
- image cache store/loader
- optional detail snapshot cache

Rules:
- port method names must use `canonicalComicId`, `upstreamComicRefId`, `chapterRefId`, not `comicId/cid/eid`
- ports accept canonical IDs for app storage and upstream IDs only where the port represents remote source material

Forbidden:
- old DB schema compatibility
- legacy managers
- SQLite identifier string construction in runtime domain/usecase layers

Owner: Agent 3 / Ports
Write scope:
- `lib/features/reader_next/runtime/session.dart`
- future `lib/features/reader_next/runtime/ports.dart`
- data-port tests under `test/features/reader_next/runtime/`

### Layer 4 - Infrastructure Adapters

Purpose:
- Implement ports using real storage/network/cache systems.
- This layer can bridge to existing app services only behind strict new interfaces.

Allowed in first slice:
- in-memory adapters for tests
- file/image cache implementation behind `ImageCacheStore`
- Drift-backed session adapter only after runtime tests pass

Forbidden:
- importing old reader UI
- importing legacy managers as runtime dependency
- old DB migration
- silent fallback to old cache key formats

Owner: Agent 4 / Infrastructure
Write scope:
- future `lib/features/reader_next/infrastructure/*`
- infra tests under `test/features/reader_next/infrastructure/`

### Layer 5 - UI Shell

Purpose:
- Render state returned by application use cases.
- Send user intents to controllers/use cases.

Allowed responsibilities:
- screen layout
- loading/error/empty state rendering
- navigation input/output

Forbidden:
- source resolution
- adapter calls
- DB migration/import
- cache key construction
- parsing canonical IDs
- deriving upstream IDs

Owner: Agent 5 / UI Shell
Write scope:
- future `lib/features/reader_next/presentation/*`
- widget tests under `test/features/reader_next/presentation/`

UI is out of scope until layers 0-3 have passing tests.

### Layer 6 - Importer / Legacy Bridge

Purpose:
- Read old DB/runtime data and import into the new canonical store.
- This is an offline/import path, not runtime.

Allowed responsibilities:
- DB backup before import
- schema detection
- row validation
- explicit import report
- dropping malformed rows with diagnostics

Forbidden:
- being imported by runtime domain/usecase/UI
- runtime fallback reads
- old DB tables as live source of truth

Owner: Agent 6 / Importer
Write scope:
- future `lib/features/reader_next/importer/*`
- importer tests under `test/features/reader_next/importer/`

Importer is out of scope for first slice.

### Layer 7 - Diagnostics

Purpose:
- Provide typed debug packets and user-safe errors.
- Keep logs redacted by default.

Allowed responsibilities:
- typed error model
- diagnostic code mapping
- redacted debug bundle
- adapter-boundary failure reporting

Forbidden:
- raw cookie/header/token export by default
- converting identity errors into generic network errors
- UI-only string parsing for error type

Owner: Agent 7 / Diagnostics
Write scope:
- future `lib/features/reader_next/diagnostics/*`
- diagnostics tests under `test/features/reader_next/diagnostics/`

## Layer Assignment Matrix

| Agent | Layer | Main Output | May Edit Runtime Authority | May Edit UI | May Touch Legacy |
| --- | --- | --- | --- | --- | --- |
| Agent 0 | Identity Domain | identity models + boundary tests | yes, identity files only | no | no |
| Agent 1 | Registry/Gateway | strict adapter gateway | yes, gateway files only | no | no |
| Agent 2 | Use Cases | vertical flow orchestration | yes, usecase files only | no | no |
| Agent 3 | Data Ports | session/cache ports | yes, port/session files only | no | no |
| Agent 4 | Infrastructure | real adapters behind ports | no until approved | no | no runtime legacy |
| Agent 5 | UI Shell | state-rendering UI | no | yes, after approval | no |
| Agent 6 | Importer | legacy import pipeline | no | no | importer-only |
| Agent 7 | Diagnostics | typed diagnostics | diagnostics files only | no | no |

Cross-layer changes require coordinator approval before editing.

## Project Tracker

Status values:
- `todo` - ready but not started
- `claimed` - assigned to an agent
- `blocked` - waiting for dependency or coordinator decision
- `review` - patch ready for coordinator review
- `done` - merged and verified

Dependency rule:
- A task may only start when every task in `Depends On` is `done`, unless coordinator explicitly marks it `unblocked`.

## Coordinator Claim Log

Coordinator: Codex (this thread)

Claimed and executed in this batch:
- M0-T2
- M1-T1
- M1-T2
- M1-T3
- M2-T1
- M2-T2
- M2-T3
- M2-T4
- M3-T1
- M3-T3
- M4-T1
- M4-T2
- M4-T4
- M5-T1
- M5-T2
- M5-T3
- M5-T4
- M9-T1
- M9-T2
- M9-T3
- M9-T4
- M9-T5
- M9-T6

## Agent Execution Protocol

Every implementation agent must follow this protocol before touching files.

Required skill:
- `superpowers:executing-plans`

Start message:

```text
I'm using the executing-plans skill to implement this plan.
```

Required first steps:
1. Read this file: `docs/plans/agent-shared.md`.
2. Read the exact files in the claimed task write scope.
3. Review the task critically before editing.
4. If the task conflicts with hard rules, file ownership, or dependencies, stop and report the blocker.
5. If no blocker exists, claim the task in your working notes and proceed.

Execution batch rule:
- Default batch size is 1 project-tracker task.
- A coordinator may approve a batch of up to 3 adjacent tasks when dependencies are already satisfied.
- Do not work on unrelated tasks in the same batch.

Per-task workflow:
1. Mark the task mentally as `claimed`.
2. Implement only within the task write scope.
3. Run the task-specific verification command.
4. Run `git diff --check`.
5. Prepare a report using the template below.
6. Stop at `review`; wait for coordinator feedback before taking the next task.

Stop immediately when:
- verification fails repeatedly
- a runtime API change is needed outside your write scope
- dependency task is not complete
- old runtime or legacy manager import appears necessary
- the only way forward is a fallback or silent normalization

Do not guess around blockers. Report them.

Completion workflow:
- After all tasks in a milestone are verified, the coordinator must run the milestone verification command.
- After all milestones in the first slice are complete, coordinator uses `superpowers:finishing-a-development-branch`.

## Task Claim Format

Agents should claim work in their opening report using this format:

```text
Agent:
Using skill: superpowers:executing-plans
Claiming task IDs:
Plan file: docs/plans/agent-shared.md
Batch size:
Expected write scope:
Expected verification:
Initial concerns:
```

If `Initial concerns` is not empty, stop before implementation.

### Milestone M0 - Runtime Authority Cleanup

Goal: make one runtime authority namespace for the first slice before broad implementation.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M0-T1 | done | Coordinator | none | `lib/features/reader_next/runtime/*` | Removed duplicate runtime mirror and selected `lib/features/reader_next/runtime/*` as sole runtime authority | `find lib -path '*venera_next*' -type f -print` |
| M0-T2 | done | Coordinator | M0-T1 | `docs/plans/agent-shared.md` | Update this contract to name only the canonical runtime namespace | manual doc review |
| M0-T3 | done | Agent 0 | M0-T1 | `test/features/reader_next/runtime/authority_*` | Guard test prevents duplicate runtime namespace and legacy reader/UI imports | `flutter test test/features/reader_next/runtime/authority_*` |

### Milestone M1 - Identity Boundary Kernel

Goal: lock canonical-vs-upstream identity rules before any real adapter or UI work.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M1-T1 | done | Agent 0 | M0-T1 | `lib/features/reader_next/runtime/models.dart` | `CanonicalComicId`, `SourceRef`, and typed boundary errors with explicit names | `dart analyze lib/features/reader_next/runtime/models.dart` |
| M1-T2 | done | Agent 0 | M1-T1 | `lib/features/reader_next/runtime/cache_keys.dart` | cache key builder using `sourceKey/canonicalComicId/upstreamComicRefId/chapterRefId/imageKey` | `flutter test test/features/reader_next/runtime/cache_key_*` |
| M1-T3 | done | Agent 0 | M1-T1 | `test/features/reader_next/runtime/boundary_*` | fail-closed tests for missing/malformed `SourceRef` | `flutter test test/features/reader_next/runtime/boundary_*` |
| M1-T4 | done | Agent 7 | M1-T1 | `lib/features/reader_next/diagnostics/*`, `test/features/reader_next/diagnostics/*` | typed diagnostics mapper for runtime boundary failures without generic collapse | `flutter test test/features/reader_next/diagnostics` |

### Milestone M2 - Source Registry + Adapter Gateway

Goal: all remote operations go through one strict gateway and adapters receive upstream IDs only.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M2-T1 | done | Agent 1 | M1-T1 | `lib/features/reader_next/runtime/adapter.dart` | adapter interface with explicit upstream parameter names | `dart analyze lib/features/reader_next/runtime/adapter.dart` |
| M2-T2 | done | Agent 1 | M2-T1 | `lib/features/reader_next/runtime/registry.dart` | strict source registry lookup by canonical `sourceKey`; no alias matching | `flutter test test/features/reader_next/runtime/registry_*` |
| M2-T3 | done | Agent 1 | M2-T1,M2-T2 | `lib/features/reader_next/runtime/gateway.dart` | gateway validates `SourceRef` before adapter call | `flutter test test/features/reader_next/runtime/gateway_*` |
| M2-T4 | done | Agent 1 | M2-T3 | `test/features/reader_next/runtime/gateway_*` | adapter spy proves only `upstreamComicRefId` crosses boundary | `flutter test test/features/reader_next/runtime/gateway_*` |

### Milestone M3 - Runtime Data Ports

Goal: storage-facing runtime code uses namespaced canonical identity only.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M3-T1 | done | Agent 3 | M1-T1 | `lib/features/reader_next/runtime/session.dart` | `ReaderSessionStore` port and in-memory implementation | `flutter test test/features/reader_next/runtime/session_*` |
| M3-T2 | done | Agent 3 | M1-T2 | `lib/features/reader_next/runtime/ports.dart` | `ImageCacheStore` port implemented with in-memory/noop stores for runtime use cases | `dart analyze lib/features/reader_next/runtime` |
| M3-T3 | done | Agent 3 | M3-T1 | `test/features/reader_next/runtime/session_*` | session keys are namespaced canonical IDs, never raw id-only | `flutter test test/features/reader_next/runtime/session_*` |

### Milestone M4 - Application Use Cases

Goal: expose UI-free flows for search/detail/page/image/session.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M4-T1 | done | Agent 2 | M2-T3,M3-T1 | `lib/features/reader_next/runtime/usecases.dart` | search use case using registry/gateway only | `flutter test test/features/reader_next/runtime/usecase_search_*` |
| M4-T2 | done | Agent 2 | M2-T3,M3-T1 | `lib/features/reader_next/runtime/usecases.dart` | detail + reader page load use cases | `flutter test test/features/reader_next/runtime/usecase_reader_*` |
| M4-T3 | done | Agent 2 | M2-T3,M3-T2 | `lib/features/reader_next/runtime/usecases.dart` | image bytes/cache use case implemented in runtime layer; UI only provides fetch callback | `flutter test test/features/reader_next/runtime/usecase_image_*` |
| M4-T4 | done | Agent 2 | M3-T1 | `lib/features/reader_next/runtime/usecases.dart` | resume save/load use case | `flutter test test/features/reader_next/runtime/usecase_resume_*` |

### Milestone M5 - Integration Harness

Goal: prove the first vertical slice works with fake adapters and no legacy runtime imports.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M5-T1 | done | Agent C | M2-T3 | `test/features/reader_next/runtime/fakes/*` | fake source adapter with call capture | `dart analyze test/features/reader_next/runtime/fakes` |
| M5-T2 | done | Agent C | M4-T1,M4-T2,M5-T1 | `test/features/reader_next/runtime/kernel_integration_*` | search -> detail -> pages integration test | `flutter test test/features/reader_next/runtime/kernel_integration_*` |
| M5-T3 | done | Agent C | M4-T3,M4-T4,M5-T1 | `test/features/reader_next/runtime/kernel_integration_*` | image key + resume session integration test | `flutter test test/features/reader_next/runtime/kernel_integration_*` |
| M5-T4 | done | Agent C | M5-T2,M5-T3 | `test/features/reader_next/runtime/kernel_integration_*` | canonical/source mismatch throws before adapter call | `flutter test test/features/reader_next/runtime/kernel_integration_*` |

### Milestone M6 - Infrastructure Adapters (After Kernel Green)

Goal: connect runtime ports to real storage/cache behind strict interfaces.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M6-T1 | done | Agent 4 | M5-T4 | `lib/features/reader_next/infrastructure/session_*` | Drift-backed `ReaderSessionStore` adapter (`DriftReaderSessionStore`) | `flutter test test/features/reader_next/infrastructure/session_*` |
| M6-T2 | done | Agent 4 | M5-T4 | `lib/features/reader_next/infrastructure/image_cache_*` | cache implementation using new tuple key only (`CacheManagerImageCacheStore`) | `flutter test test/features/reader_next/infrastructure/image_cache_*` |
| M6-T3 | done | Agent 4 | M6-T1,M6-T2 | `test/features/reader_next/infrastructure/*` | infrastructure tests pass with no legacy runtime dependency | `flutter test test/features/reader_next/infrastructure` |

### Milestone M7 - UI Shell (After Kernel + Infra)

Goal: build UI as a thin state renderer over use cases.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M7-T1 | done | Agent 5 | M5-T4 | `lib/features/reader_next/presentation/*` | thin UI shell + controller calling runtime use cases only (no adapter/DB/cache-key logic in UI) | `dart analyze lib/features/reader_next/presentation` |
| M7-T2 | done | Agent 5 | M7-T1 | `test/features/reader_next/presentation/*` | widget tests for loading/error/content states | `flutter test test/features/reader_next/presentation` |

### Milestone M8 - Importer (Separate Lane)

Goal: import old DB/runtime data without making legacy schema runtime authority.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M8-T1 | done | Agent 6 | M5-T4 | `lib/features/reader_next/importer/*` | DB backup + schema detection preflight scaffold (`LegacyImportPreflightService`) | `flutter test test/features/reader_next/importer` |
| M8-T2 | done | Agent 6 | M8-T1 | `lib/features/reader_next/importer/*` | row validation + structured import report (`LegacyImportValidationService`) | `flutter test test/features/reader_next/importer` |
| M8-T3 | done | Agent 6 | M8-T2 | `test/features/reader_next/importer/*` | malformed legacy rows skipped with explicit diagnostic codes and counts | `flutter test test/features/reader_next/importer` |

### Milestone M9 - Importer Execution Mode (Follow-up Lane)

Goal: run importer end-to-end in explicit dry-run/apply modes with checkpoint/resume and fail-closed runtime isolation.

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M9-T1 | done | Coordinator | M8-T3 | `lib/features/reader_next/importer/models.dart` | execution-mode models for dry-run/apply, checkpoint, and execution report | `dart analyze lib/features/reader_next/importer/models.dart` |
| M9-T2 | done | Coordinator | M9-T1 | `lib/features/reader_next/importer/legacy_import_execution.dart` | importer execution service with strict `LegacyImportApplySink` boundary and no runtime dependency | `dart analyze lib/features/reader_next/importer/legacy_import_execution.dart` |
| M9-T3 | done | Coordinator | M9-T2 | `lib/features/reader_next/importer/legacy_import_execution.dart` | dry-run artifact output with backup/preflight/validation snapshot | `flutter test test/features/reader_next/importer/execution_test.dart --plain-name \"dry-run\"` |
| M9-T4 | done | Coordinator | M9-T2 | `lib/features/reader_next/importer/legacy_import_execution.dart`, `test/features/reader_next/importer/execution_test.dart` | checkpoint/resume apply flow with rowid cursor persistence | `flutter test test/features/reader_next/importer/execution_test.dart --plain-name \"resume from checkpoint\"` |
| M9-T5 | done | Coordinator | M9-T2 | `test/features/reader_next/importer/execution_test.dart` | apply failure surfaced as structured non-completed execution report with failure code | `flutter test test/features/reader_next/importer/execution_test.dart --plain-name \"reports apply failure\"` |
| M9-T6 | done | Coordinator | M9-T2 | `lib/features/reader_next/importer/importer_coordinator.dart`, `test/features/reader_next/importer/coordinator_test.dart` | importer-only coordinator entrypoint that delegates dry-run/apply without runtime coupling | `flutter test test/features/reader_next/importer/coordinator_test.dart` |

### Milestone M10 - ReaderNext Production Cutover Preflight

Goal: prepare ReaderNext for production routing by adding a strict bridge boundary between legacy app entrypoints and the new runtime. This lane does not replace the legacy reader yet.

Detailed implementation plan:
- `docs/plans/2026-05-01-readernext-production-cutover-preflight.md`

Hard Rules (M10 preflight specific):
1. ReaderNext runtime remains the only authority for identity/cache/session/page-load rules.
2. Legacy app models may enter ReaderNext only through `reader_next/bridge`.
3. Remote ReaderNext open requests require a non-null validated `SourceRef`.
4. Bridge code must reject canonical IDs in adapter-facing/upstream fields.
5. Bridge code must never silently normalize `remote:source:id` into `id`.
6. Legacy reader remains available only through explicit legacy route.
7. ReaderNext UI receives `ReaderNextOpenRequest`, never raw `Comic`, `History`, or `FavoriteItem`.
8. Failures produce typed bridge diagnostics, not generic network errors.

Key boundary tests:

```dart
test('remote ReaderNext open request requires SourceRef', () {
  final sourceRef = SourceRef.remote(
    sourceKey: 'nhentai',
    upstreamComicRefId: '646922',
    chapterRefId: '0',
  );
  final request = ReaderNextOpenRequest.remote(
    canonicalComicId: CanonicalComicId.remote(
      sourceKey: 'nhentai',
      upstreamComicRefId: '646922',
    ),
    sourceRef: sourceRef,
    initialPage: 1,
  );
  expect(request.sourceRef, sourceRef);
});
```

```dart
test('bridge rejects canonical id as upstreamComicRefId', () {
  expect(
    () => SourceRef.remote(
      sourceKey: 'nhentai',
      upstreamComicRefId: 'remote:nhentai:646922',
      chapterRefId: '0',
    ),
    throwsA(isA<ReaderNextBoundaryException>()),
  );
});
```

```dart
test('ReaderNext bridge does not silently normalize canonical upstream id', () {
  final result = ReaderNextOpenBridge.fromLegacyRemote(
    sourceKey: 'nhentai',
    comicId: 'remote:nhentai:646922',
    chapterId: '0',
  );
  expect(result.isBlocked, isTrue);
  expect(
    result.diagnostic?.code,
    ReaderNextBridgeDiagnosticCode.canonicalIdInUpstreamField,
  );
});
```

### M10 - Bridge Boundary + Route Preflight

| Task ID | Status | Owner | Depends On | Write Scope | Deliverable | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| M10-T1 | done | Coordinator | M7-T2,M9-T6 | `lib/features/reader_next/bridge/*` | `ReaderNextOpenRequest` + typed bridge diagnostics | `flutter test test/features/reader_next/bridge/open_request_*` |
| M10-T2 | done | Coordinator | M10-T1 | `test/features/reader_next/bridge/*` | bridge rejects missing SourceRef, canonical upstream ID, empty sourceKey, empty chapterRefId | `flutter test test/features/reader_next/bridge` |
| M10-T3 | done | UI Agent | M10-T1 | `lib/features/reader_next/presentation/*` | presentation controller accepts only `ReaderNextOpenRequest` | `flutter test test/features/reader_next/presentation` |
| M10-T4 | done | Coordinator | M10-T1 | `test/features/reader_next/runtime/authority_*` | guard test blocks old reader/UI/legacy manager imports from ReaderNext runtime/presentation | `flutter test test/features/reader_next/runtime/authority_*` |
| M10-T5 | done | Coordinator | M10-T2,M10-T3 | `lib/features/reader_next/bridge/*`, `test/features/reader_next/bridge/*` | explicit legacy-route decision object: `readerNext`, `legacyReader`, or `blocked` | `flutter test test/features/reader_next/bridge` |

## Agent Report Template

Each agent must end with this report:

```text
Agent:
Claimed task IDs:
Files changed:
Runtime API changes requested:
Tests run:
Result:
Blocked by:
Next recommended task:
```

## Subagent Work Split

### Agent A - Boundary + Gateway Tests
- Add tests for `ComicIdentity.assertRemoteOperationSafe` and gateway boundary checks.
- Verify fail-closed errors:
  - missing `SourceRef`
  - empty `sourceKey`
  - empty `upstreamComicRefId`
  - `upstreamComicRefId` containing `:`
- Verify adapter receives `upstreamComicRefId` only.

### Agent B - Session + Cache Identity Tests
- Add tests for namespaced canonical keys in `ReaderSessionStore`.
- Add tests for image cache key composition completeness and order:
  - `sourceKey`
  - `canonicalComicId`
  - `upstreamComicRefId`
  - `chapterRefId`
  - `imageKey`
- Verify no `id`-only key format remains in new kernel.

### Agent C - Integration Adapter Stub Harness
- Build fake adapter for search/detail/pages/image.
- Add runtime tests covering:
  - search by sourceKey
  - detail load
  - page load
  - resume save/load
- Assert canonical ID mismatch throws.

## File Ownership (Do Not Overlap)

- Agent A write scope:
  - `test/features/reader_next/runtime/boundary_*`
  - `test/features/reader_next/runtime/gateway_*`
- Agent B write scope:
  - `test/features/reader_next/runtime/session_*`
  - `test/features/reader_next/runtime/cache_key_*`
- Agent C write scope:
  - `test/features/reader_next/runtime/kernel_integration_*`
  - `test/features/reader_next/runtime/fakes/*`
- Coordinator-only write scope:
  - `lib/features/reader_next/runtime/*`
  - this plan file

If a subagent needs runtime API change, it must only propose patch notes in its report.  
Coordinator applies runtime API edits to avoid merge conflicts.

## Copy/Paste Task Packets

### Packet A (Boundary + Gateway)

```text
Task: Implement fail-closed boundary tests for reader-next runtime.
Goal:
- verify missing SourceRef fails closed
- verify malformed upstreamComicRefId fails closed
- verify adapter receives upstreamComicRefId only (never canonical id)
Write scope:
- test/features/reader_next/runtime/boundary_*.dart
- test/features/reader_next/runtime/gateway_*.dart
Constraints:
- do not edit runtime implementation files
- do not touch legacy reader tests
Output:
1) changed file list
2) failing assertions before fix expectation
3) final passing test command output summary
```

### Packet B (Session + Cache Identity)

```text
Task: Implement identity namespace and cache key tests for reader-next runtime.
Goal:
- verify reader session key is namespaced canonical id
- verify cache key includes exact tuple:
  sourceKey, canonicalComicId, upstreamComicRefId, chapterRefId, imageKey
- verify no id-only key behavior in this runtime surface
Write scope:
- test/features/reader_next/runtime/session_*.dart
- test/features/reader_next/runtime/cache_key_*.dart
Constraints:
- do not edit runtime implementation files
- do not add fallback behavior
Output:
1) changed file list
2) assertions added
3) final passing test command output summary
```

### Packet C (Kernel Integration Harness)

```text
Task: Build fake adapter harness + kernel integration tests.
Goal:
- search/detail/page/image/resume flow through runtime kernel
- canonical/source mismatch must throw
- remote operation without SourceRef must fail before adapter call
Write scope:
- test/features/reader_next/runtime/kernel_integration_*.dart
- test/features/reader_next/runtime/fakes/*
Constraints:
- no UI tests
- no legacy runtime imports
Output:
1) changed file list
2) fake adapter contract
3) final passing test command output summary
```

## Coordinator Merge Order

1. Merge Agent A tests (boundary)
2. Merge Agent B tests (identity key policy)
3. Merge Agent C integration tests
4. Apply minimal runtime implementation edits only if tests expose gaps
5. Run full verification for this slice

## Acceptance Criteria

1. New kernel tests pass independently from old reader tests.
2. Any remote operation without valid `SourceRef` fails before adapter call.
3. Adapter-facing methods have explicit upstream ID naming.
4. No new code in this lane uses ambiguous `cid/eid/comicId` for mixed semantics.
5. No UI file added in this slice.

## Milestone Closeout (M0-M8)

Closeout status:
- `M0` done: runtime authority consolidated to `lib/features/reader_next/runtime/*`.
- `M1` done: identity boundary + typed diagnostics mapping in place.
- `M2` done: registry/gateway path enforces upstream-only adapter boundary.
- `M3` done: runtime data ports established for session + image cache.
- `M4` done: use cases implemented for search/detail/page/image/resume.
- `M5` done: integration harness verifies vertical slice behavior.
- `M6` done: infrastructure adapters implemented and tested.
- `M7` done: thin UI shell + widget tests with no runtime-boundary violations.
- `M8` done: importer preflight + validation/report + malformed-row skip diagnostics.

Residual risks (post-closeout):
- Importer currently validates and reports rows but does not yet persist imported data into canonical runtime tables as a full transactional migration command.
- No explicit rollback/retry orchestration wrapper exists yet for long-running import sessions.
- Reader-next shell is a minimal vertical slice; production routing/integration with existing app navigation is not wired in this plan.

Recommended next lane:
- Add `M9` for importer execution mode (transactional apply, resume checkpoint, dry-run export, and rollback strategy).

## Verification Commands

```bash
flutter test test/features/reader_next
dart analyze lib/features/reader_next test/features/reader_next
git diff --check
```

## Handoff Notes

- Do not refactor old runtime in the same patch as kernel work.
- Keep kernel patches narrow and reviewable.
- If temporary bridge is needed, put it outside `lib/features/reader_next/runtime/*` and mark as temporary.
- The sole runtime authority namespace is `lib/features/reader_next/runtime/*`.
