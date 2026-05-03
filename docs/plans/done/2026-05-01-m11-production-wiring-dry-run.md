# M11 Production Wiring Dry-Run Plan

Goal: wire exactly one controlled production entrypoint to ReaderNext behind a feature flag, then prove all production open paths stay bridge-only.

Scope boundary:
- This milestone is wiring verification only.
- Do not roll out full cutover to history/favorites/download paths.
- First production wiring target is comic detail open path only.

## Hard Rules

1. Existing app pages must not construct `ReaderNextOpenRequest` directly.
2. Existing app pages must call only `ReaderNextOpenBridge` for ReaderNext route preparation.
3. Feature flag `reader_next_enabled` defaults to `false`.
4. Missing/malformed `SourceRef` must render typed blocked state; no legacy fallback in ReaderNext path.
5. Legacy reader route remains explicit and separate.
6. Old reader files must not import `reader_next/runtime`.
7. Feature flag controls route selection only and must never relax ReaderNext boundary checks.
8. ReaderNext bridge failure is a terminal route decision for this entrypoint.

## Feature Flag Semantics

`reader_next_enabled` controls route selection only.

Allowed:
- `false`: always use explicit legacy reader route.
- `true`: attempt ReaderNext bridge for approved entrypoint only.

Forbidden:
- using the flag to bypass `SourceRef` validation
- falling back to legacy after ReaderNext bridge failure
- silently rebuilding `SourceRef` from raw `comic.id`
- enabling ReaderNext for history/favorites/download paths

## Preflight Guard Commands

```bash
rg -n "ReaderNextOpenRequest\\(" lib -g '!lib/features/reader_next/**' -g '!*.g.dart'
rg -n "ReaderNextOpenBridge" lib/features -g '!lib/features/reader_next/**' -g '!*.g.dart'
```

Expected:
- first command: no output (constructor-pattern guard against direct request construction)
- second command: no output before wiring; after M11-T2 only approved entrypoint is allowed

## Approved Production Wiring Exception

Approved exception after M11-T2:
- exactly one production file outside `lib/features/reader_next/**` may reference `ReaderNextOpenBridge`
- approved file:
  - `lib/pages/comic_detail_page.dart`
- approved file constraints:
  - may import/use `ReaderNextOpenBridge`
  - must not construct `ReaderNextOpenRequest`
  - must not import ReaderNext runtime files
  - must not import ReaderNext presentation page/screen directly

If implementation needs a helper/controller, put it under:
- `lib/features/reader_next/bridge/`
- `lib/features/reader_next/presentation/`

Existing production pages may call only the approved bridge-facing function exposed by the comic-detail wiring path.

## Task Table

| Task ID | Deliverable | Verification |
| --- | --- | --- |
| M11-T1 | add feature flag `reader_next_enabled` with default `false` | settings/service unit test |
| M11-T2 | wire one bridge entrypoint from comic detail page only | page/controller/widget test |
| M11-T3 | add guard test: no production page constructs `ReaderNextOpenRequest` directly | authority/grep-backed test |
| M11-T4 | add blocked-state UI for bridge failure (typed diagnostic rendering) | widget test |
| M11-T5 | add cutover dry-run diagnostic packet with redacted identity fields | presentation/runtime test |
| M11-T6 | add route/import authority guard for ReaderNext production wiring | authority/grep-backed test |

## M11-T2 Entrypoint Contract

Approved production entrypoint:
- comic detail page `Read/Open Reader` action only
- input must include current `ComicDetails` plus a valid `SourceRef`
- bridge output is strictly one of:
  - `ReaderNextOpenRequest`
  - typed blocked result

## M11-T5 Diagnostic Packet Contract

Dry-run diagnostic packet must include:
- `routeDecision`: `legacy | readerNext | blocked`
- `sourceKey`
- `canonicalComicIdHash` or redacted canonical ID
- `upstreamComicRefIdHash` or redacted upstream ID
- `chapterRefIdHash` or redacted chapter ID
- `bridgeResultCode`
- `featureFlagEnabled`

Acceptance test to add:

```dart
test('comic detail entrypoint does not fall back to legacy when ReaderNext bridge blocks', () {
  // flag on + malformed SourceRef => blocked state
  // assert legacy open callback was not called
});

test('feature flag does not relax ReaderNext SourceRef validation', () {
  // flag on + canonical id injected as upstreamComicRefId
  // expect typed blocked result
  // assert ReaderNext route callback was not called
  // assert legacy route callback was not called
});
```

## Additional Authority Guards

M11 must also prove:
1. No production page opens ReaderNext presentation route directly.
   Existing app code must go through the approved comic-detail controller/bridge path only.
2. Legacy reader/runtime files must not import any `reader_next/*` package.
   ReaderNext may bridge outward from approved bridge code, but old runtime must not depend inward on ReaderNext.

Recommended guard commands:

```bash
rg -n "ReaderNext.*Page|ReaderNext.*Screen|OpenReaderController" lib -g '!lib/features/reader_next/**' -g '!*.g.dart'
rg -n "features/reader_next" lib/pages lib/foundation lib/components -g '!*.g.dart'
```

Expected:
- first command: only approved comic-detail wiring file may appear after M11-T2
- second command after M11-T2:
  - output allowed only from `lib/pages/comic_detail_page.dart`
  - output must reference bridge only
  - no output from `lib/foundation` or `lib/components`
  - no output referencing `reader_next/runtime`
  - no output referencing ReaderNext presentation page/screen classes

Approved exception after M11-T2:
- exactly one production file may reference `ReaderNextOpenBridge`
- approved file:
  - `lib/pages/comic_detail_page.dart`
- no production file may reference `ReaderNextOpenRequest(`
- no production file may reference ReaderNext presentation classes directly

## Risk Notes

- History/favorites/download flows are intentionally excluded in this milestone.
- Those paths often lack complete `SourceRef` fields and should only be wired after canonical session/importer identity backfill is verified.

## Exit Criteria

- M11-T1..T6 all green.
- Guard commands remain clean except the single approved comic-detail bridge entrypoint.
- No production page constructs `ReaderNextOpenRequest` directly.
- No production page opens ReaderNext presentation route directly.
- No legacy reader/runtime/component directory imports `reader_next/*`.
- No legacy fallback introduced after ReaderNext bridge failure.

## M11 Closeout Authority Note

Approved production bridge file:
- `lib/pages/comic_detail_page.dart`

Comic details legacy page files may call that wrapper only.
They must not import ReaderNext bridge/runtime/presentation directly.
