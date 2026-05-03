# AppData Owner Decisions

## Scope

Decision-only slice.

- record owner decisions for audited appdata / implicitData keys
- make ownership assumptions explicit in docs and tests
- no runtime behavior change
- no schema/default change
- no migration/deletion

## Decision Table

| Key | Storage | Current use | Decision | Rationale | Follow-up lane |
| --- | --- | --- | --- | --- | --- |
| `reader_use_resume_source_ref_snapshot` | `appdata.settings` | no runtime reader; retired migration flag residue | **Retire as runtime flag** | runtime previously read an undeclared flag; this hidden branch made resume behavior non-obvious, and `A-appdata-migrate-1a` already moved legacy resume snapshot loading behind explicit `ReaderResumeService` fallback injection | `A-appdata-migrate-1b`: keep `ReaderResumeService(loadLegacyResumeSourceRef: ...)` as the explicit compatibility path; do not add schema/default for this key |
| `reading_resume_targets_v1` | `appdata.implicitData` | `ResumeTargetStore` resume snapshot cache | **Legacy fallback bridge** | canonical `reader_sessions` already exists in DB; this snapshot must not remain canonical authority | `A-appdata-migrate-1`: evaluate read-only fallback / sunset plan after reader session migration |
| `comicSourceListUrl` | `appdata.settings` | legacy source repository URL, still read by init/seed and legacy UI path | **Legacy source repository bridge** | repository registry is canonical authority after M26.2; this key remains for seed/import fallback only | `A-appdata-migrate-1` or source-registry follow-up: remove direct UI authority and sunset bridge reads |
| `followUpdatesFolder` | `appdata.settings` | follow-updates page selection / workflow state | **UI workflow state** | value selects the active updates folder but does not own source/update authority | keep in appdata unless the follow-updates workflow gets a dedicated state owner |

## Explicit Non-Decisions

These are intentionally **not** part of this slice:

- no new `SettingKey<bool>('reader_use_resume_source_ref_snapshot')`
- no default value for `reader_use_resume_source_ref_snapshot`
- no rewrite of `reading_resume_targets_v1` into `reader_sessions`
- no deletion of `comicSourceListUrl`
- no move of `followUpdatesFolder` out of `appdata.settings`

## Testing Contract

Owner assumptions must remain executable via the appdata audit registry tests:

```text
test('resume source ref snapshot owner decision remains explicit', () async {});
test('resume source ref snapshot flag owner decision is retire as runtime flag', () async {});
test('resume source ref snapshot flag remains undeclared and has no default in owner decision slice', () async {});
test('reader resume legacy fallback remains owned by ReaderResumeService decision', () async {});
test('comic source list url is classified as legacy source repository bridge', () async {});
test('reading resume targets are legacy fallback after canonical reader sessions', () async {});
test('follow updates folder remains ui workflow state and not authority', () async {});
```

## Migration Boundary

Migration is a separate lane.

```text
A-appdata-owner-1 / A-appdata-owner-2 = ownership decisions only
A-appdata-migrate-1 = behavior/storage migration only
```
