# Source Runtime Account + Request Policy Core

## Problem

Comic source JavaScript currently owns too much mutable runtime behavior. Sources can directly manage account state, cookies, request headers, retry behavior, cooldowns, and ad hoc error handling. This creates inconsistent behavior across account login, account switching, blocked requests, and parser failures.

The current model also makes multi-account support risky. If requests read active account state at execution time, queued or retried requests may run with different credentials than originally bound.

## Goals

- Move mutable runtime state ownership into Dart.
- Make the request pipeline the only owner of request-time headers, cookies, retry, cooldown, and diagnostics behavior.
- Support multi-account profiles with immutable request-time account snapshots.
- Keep JavaScript source logic bounded to source-specific hooks and parsers.
- Add stable diagnostics taxonomy so legacy and new runtime failures can be reported consistently.
- Keep legacy sources working through a best-effort adapter.
- Add protected-origin classification boundaries for runtime safety and deterministic failures.

## Non-goals

- Do not replace all existing source APIs in one change.
- Do not require every existing source to migrate immediately.
- Do not promise perfect diagnostics classification for legacy throw strings.
- Do not build a full Source SDK v2 in Phase 1.
- Do not implement custom cryptographic storage.
- Do not bypass anti-bot/CAPTCHA protections.
- Do not include source distribution/store platform work in Phase 1.
- Do not include source-scoped i18n catalog loading in Phase 1.
- Do not include explorer/discovery product redesign in Phase 1.

## Ownership Model

Dart owns mutable runtime state and lifecycle:

- account profile index
- account secrets
- active profile selection
- request-time account snapshots
- cookie application
- header profile application
- retry, queue, cooldown, response classification, and diagnostics

JavaScript sources provide bounded source-specific behavior:

- declarative capabilities and account metadata
- URL/payload builders
- parsers
- executable hooks with structured input/output

Use precise wording: runtime-owned lifecycle with source-provided bounded hooks.

## Runtime Architecture

Phase 1 introduces:

- `ComicSourceRuntimeRequest`: single request entrypoint for source-owned network calls.
- `ComicSourceAccountStore`: per-source profile index plus secure secret references.
- `ComicSourceAccountManager`: profile CRUD, active selection, validation orchestration.
- `ComicSourceRequestPolicy`: retry, cooldown, queue, response classification decisions.
- `ComicSourceDiagnostics`: structured error codes and stage-aware reporting.
- `LegacyComicSourceAdapter`: behavior-preserving legacy path with opportunistic diagnostics mapping.

Request pipeline authority:

```text
ComicSourceRuntimeRequest
  -> create immutable SourceRequestContext
  -> bind account profile snapshot
  -> apply HeaderProfile
  -> read CookieJar for snapshot profile
  -> apply RequestPolicy
  -> execute HTTP
  -> classify response
  -> emit Diagnostics
```

Account manager must not mutate in-flight request headers. Account switching affects new contexts only.

## Data Model

Non-secret account metadata is stored in source-scoped account index:

```json
{
  "version": 1,
  "sourceKey": "ehentai",
  "activeProfileId": "profile_1",
  "profiles": [
    {
      "id": "profile_1",
      "label": "Main",
      "fieldNames": ["ipb_member_id", "ipb_pass_hash", "igneous", "star"],
      "cookieDomains": [".e-hentai.org", ".exhentai.org"],
      "secretRef": "comic_source_accounts/ehentai/profile_1",
      "revision": 3,
      "createdAt": "2026-04-28T00:00:00.000Z",
      "lastUsedAt": "2026-04-28T00:00:00.000Z"
    }
  ]
}
```

Secret values are never stored in ordinary source data:

```text
comic_source_accounts/{sourceKey}/{profileId}
comic_source_account_index/{sourceKey}
```

Profile `revision` increments when credential-like material changes.

## Secret Boundary

Credential-like data includes cookie fields, tokens, passwords, and validation secrets.

Rules:

- Do not store secrets in ordinary source data.
- Use platform secure storage abstraction.
- Do not hand-roll crypto or use plain encrypted JSON as primary store.

Capability flags required on secure storage abstraction:

- `supportsHardwareBackedKeys`
- `supportsNonExportableKeys`
- `supportsBiometricOrDeviceAuthGate`
- `supportsBulkSecretStorage`

If a platform is weaker, secrets remain isolated from source data, and export/debug surfaces must label effective protection level.

## Request Flow

Each request creates immutable context:

```dart
class SourceRequestContext {
  final String sourceKey;
  final String requestId;
  final String? accountProfileId;
  final int? accountRevision;
  final String? headerProfile;
  final DateTime createdAt;
}
```

Execution steps:

1. Resolve source and requested header profile.
2. Create `SourceRequestContext`.
3. Resolve account snapshot using `accountProfileId` + `accountRevision`.
4. Apply header profile.
5. Load snapshot-bound cookies/credentials.
6. Execute request through runtime HTTP client.
7. Classify response through runtime policy and optional hook.
8. Emit structured diagnostics.

Snapshot behavior:

- If profile deleted before execution: `ACCOUNT_PROFILE_UNAVAILABLE`.
- If profile exists but revision mismatches: `ACCOUNT_REVISION_MISMATCH`.
- Future optional policy: allow stale revision only for explicitly idempotent reads.

## Account Switching Semantics

- New requests bind current active profile unless caller provides explicit profile id.
- Queued requests keep original profile id + revision.
- Retries use same request context.
- Cooldown keys include source + domain, and profile id when block is account-specific.
- Logout clears active pointer and selected session material; profile deletion is explicit.

## Source Hooks Contract

Hooks are executable, source-specific, and bounded.

Initial hooks:

- `AccountValidatorHook`
- `ResponseClassifierHook`

Future hooks:

- `SessionRecoveryHook`

Hook constraints:

- Structured input and structured output only.
- Must not mutate account store, cookie jar, request headers, or global runtime state.
- Runtime-enforced timeout.
- Hook timeout/failure fail closed.

Hook boundary recommendation:

- Hook API must be JSON input/output.
- Runtime should treat hooks as message-passing boundaries, even if first implementation reuses current JS engine.
- This preserves compatibility with future isolate/out-of-process execution.

Response classifier fallback (required behavior):

- preserve HTTP status and content-type metadata
- do not parse protected/challenge-looking HTML as normal comic content
- map unknown non-2xx to `HTTP_UNEXPECTED_STATUS`
- map challenge-looking page to `SOURCE_CHALLENGE_REQUIRED` only if runtime detector matches
- continue normal parser path only for expected status/content-type combinations

## Anti-Bot and Protected Origins

Protected origins (Cloudflare challenge pages, bot mitigation interstitials, JS challenges) are explicit runtime states, not generic parser errors.

Policy:

- detect protected/challenge responses before parser stage where possible
- classify with explicit diagnostics
- avoid infinite automated retry loops on challenge pages
- keep behavior policy-compliant and best-effort (no bypass automation)

## Diagnostics Taxonomy

Phase 1 error codes:

```text
ACCOUNT_MISSING_FIELD
ACCOUNT_SECRET_UNAVAILABLE
ACCOUNT_PROFILE_UNAVAILABLE
ACCOUNT_REVISION_MISMATCH
ACCOUNT_VALIDATION_FAILED
COOKIE_EXPIRED
COOKIE_APPLY_FAILED
SECURE_STORAGE_UNAVAILABLE
REQUEST_COOLDOWN
REQUEST_TIMEOUT
HTTP_BLOCKED
HTTP_UNEXPECTED_STATUS
HEADER_PROFILE_UNKNOWN
PARSER_EMPTY_RESULT
PARSER_INVALID_CONTENT
SOURCE_CAPABILITY_MISSING
SOURCE_CHALLENGE_REQUIRED
SOURCE_HOOK_FAILED
SOURCE_HOOK_TIMEOUT
SOURCE_HOOK_INVALID_RESULT
```

Runtime error envelope:

```dart
class SourceRuntimeError {
  final String code;
  final String message;
  final String sourceKey;
  final String? requestId;
  final String? accountProfileId;
  final SourceRuntimeStage stage;
  final Object? cause;
}

enum SourceRuntimeStage {
  account,
  request,
  responseClassification,
  parser,
  session,
  storage,
  legacy,
}
```

UI requirement in Phase 1:

- runtime emits stable `code` + developer message
- UI maps known codes to app-owned localized user messages
- hook-provided text is debug metadata, not primary user-facing copy

## Legacy Compatibility

Legacy sources continue using existing APIs. Adapter behavior is preserve-first.

Diagnostics mapping is best-effort only; legacy throw strings may map to generic runtime codes.

## Migration Plan

### Phase 1 - Runtime Account + Request Core

1. Add `SourceRuntimeError`, `SourceRuntimeStage`, and stable diagnostics codes.
2. Add secure account store abstraction + source-scoped account index.
3. Add immutable `SourceRequestContext`.
4. Add runtime request bridge.
5. Add `HeaderProfile` application in runtime pipeline.
6. Add cookie loading from profile snapshot.
7. Add `AccountValidatorHook`.
8. Add `ResponseClassifierHook` + strict fallback behavior.
9. Add legacy best-effort diagnostics adapter.
10. Migrate one reference source (preferably e-hentai/exhentai).

### Phase 2 - Platform Expansion

- `SessionRecoveryHook`
- protected-origin WebView recovery flow
- source feed signing/provenance
- source hub/store UI
- source-scoped i18n catalogs
- shared explorer descriptors

## Test Plan

Unit tests:

- profile CRUD and active switching
- secrets never stored in ordinary source data
- export excludes secrets by default
- import requires secret revalidation
- `SourceRequestContext` immutability
- retry uses same request context
- queued request keeps original profile snapshot after account switch
- deleted profile snapshot -> `ACCOUNT_PROFILE_UNAVAILABLE`
- revision mismatch -> `ACCOUNT_REVISION_MISMATCH`
- hook timeout -> fail-closed diagnostics
- malformed hook payload -> `SOURCE_HOOK_INVALID_RESULT`
- legacy mapping remains best-effort without behavior regression

Integration tests:

- add source with legacy account config
- add source with runtime account config
- switch accounts while requests are queued
- cookie-based login validation hook
- blocked/challenge response classification
- challenge/interstitial response -> `SOURCE_CHALLENGE_REQUIRED`

Security tests:

- no secret values in logs
- no secret values in standard source export
- hooks cannot mutate runtime-owned account/cookie state
- weak-storage platforms are explicitly labeled in protection metadata

## Future Work

### Source Distribution Model

- built-in vs managed feed channels
- feed signing, provenance, revoke list, kill-switch
- custom feed governance

Implementation planning should move to:
`docs/plans/source-distribution-and-feed-security.md`

### Localization Contract

Phase 2 only:

- source-scoped JSON catalogs
- locale aliasing + deterministic fallback
- missing-key telemetry policies

### Explorer and Discovery Surface

Phase 2 only:

- normalized `ExploreDescriptor` for source hub preview
- shared discovery telemetry and permission UX

## Open Questions

- Which secure storage package/abstraction should be used per platform?
- Should cooldown scope default to domain-only or domain+profile?
- What timeout defaults should be used for validation/classification hooks?
- Which source should be first migrated reference source?
- How should UI communicate unsupported protected-origin states without encouraging bypass behavior?
