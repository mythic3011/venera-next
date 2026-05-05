# venera

> [!WARNING]
> This fork is a breaking-change, personal-use-first fork.
>
> The original upstream repository is archived/read-only and is no longer treated
> as the architecture authority for this fork. Archived GitHub repositories are
> read-only and commonly indicate that a project is no longer actively
> maintained. See GitHub's repository archiving documentation:
> https://docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories
>
> This fork is maintained by `mythic3011` on a best-effort basis. It is not a
> guaranteed support service and does not promise backward compatibility with the
> old fragmented runtime/storage design.

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/mythic3011/venera)](https://github.com/mythic3011/venera/blob/master/LICENSE)
[![stars](https://img.shields.io/github/stars/mythic3011/venera?style=flat)](https://github.com/mythic3011/venera/stargazers)
[![Download](https://img.shields.io/github/v/release/mythic3011/venera)](https://github.com/mythic3011/venera/releases)

A comic reader for local and network comics.

## Fork Direction

This fork is not a conservative maintenance fork.

The old codebase is treated as a legacy reference and extraction source, not as
an architecture that must be preserved. The current direction is closer to a
runtime/data-model restructure than a small refactor.

The main goal is to extract useful behavior from the legacy implementation and
rebuild the live runtime around clear ownership boundaries:

- UI expresses user intent only.
- Application/use-case services coordinate flows.
- Domain models define stable identity and rules.
- Repositories access canonical storage.
- Database code owns schema, migration, and transactions.
- Runtime code owns loading, reader execution, and source execution.
- Diagnostics report identity, authority, lifecycle phase, and correlation.
- Legacy code must not own live runtime authority.

This fork may simplify, replace, or remove legacy architecture when it blocks:

- local/remote comic management
- source/provider identity
- tags and metadata
- chapters and page ordering
- reader sessions
- source installation
- routing ownership
- database ownership
- diagnostics and debugging

## Legacy Quarantine Policy

Legacy code may remain temporarily for reference, extraction, or migration.
However, new runtime code must not depend on legacy paths as authority.

Legacy compatibility surfaces under review include:

```text
local.db
history.db
local_favorite.db
implicitData.json
fragmented local databases
mixed app/domain state in JSON files
runtime identity derived from legacy IDs/source keys
UI-built reader SourceRef values
reader fallback state stored outside canonical sessions
unclear ownership boundaries across routing, models, storage, and diagnostics
```

The intended direction is:

```text
core/database/        DB connection, schema, migration, write gates
core/diagnostics/     structured diagnostics and exportable evidence
features/reader/      reader identity, open contracts, runtime, sessions
features/comic_library/ comic, chapter, page, and page-order domain
features/local_import/  import pipeline and canonical page ordering
features/sources/     source/provider manifests and source runtime
features/favorites/   favorite domain and persistence
features/settings/    preferences/config only
legacy/               quarantined legacy reference or migration code
```

The rule is:

```text
shared DB file is acceptable
shared god database API is not
```

## Data Compatibility Policy

This fork may introduce breaking changes to local data storage.

New versions may:

- create a new canonical database
- stop writing legacy DB files
- provide only best-effort import from old stores
- drop old compatibility paths
- reset or rebuild local metadata if the old format is unsafe or inconsistent

Old local data stores are optional import sources only. They are not permanent
runtime contracts.

A storage surface must not become authoritative only because some function can
read it. New storage-backed work must identify whether a store is:

- canonical authority
- compatibility fallback
- cache
- preference/config
- diagnostic-only state

Expected future layout:

```text
data/venera.db         canonical domain DB
blobs/                 covers, pages, imports, cache files
plugins/comic_source/  comic source implementation files
logs/                  diagnostics and exported logs
config/                app preferences only
cookies/               optional auth/session storage
```

The following old domain stores should not remain long-term runtime truth:

```text
local.db
history.db
local_favorite.db
implicitData.json
```

## Reader Runtime Direction

The reader is moving toward a canonical runtime path.

The old reader UI/routing path is treated as untrusted when it creates or
repairs runtime identity. The desired reader flow is:

```text
UI intent
  -> ReaderOpenTargetResolver
  -> resolved ReaderOpenTarget
  -> validated ReaderOpenRequest
  -> canonical reader runtime
  -> page list load
  -> image provider
  -> decode/render
  -> canonical reader session persistence
```

The following legacy pattern should not remain in live runtime:

```text
UI builds SourceRef
  -> route accepts incomplete identity
  -> ReaderWithLoading repairs chapter
  -> legacy resume fallback reads appdata
  -> session repairs active tab
  -> diagnostics hides invalid state
```

Reader runtime must not represent unresolved targets as placeholder IDs such as:

```text
local:local:<comicId>:_
```

Unresolved reader targets should return typed failures and emit structured
diagnostics instead.

## Database And Model Direction

The fork is moving away from positional string IDs that encode multiple domain
relationships into one value.

Bad pattern:

```text
local:local:<comicId>:<chapterId>
```

Preferred pattern:

```text
DB authority:       columns + foreign keys
Runtime authority:  typed domain objects
Debug/log view:     rendered readable references
```

In other words:

```text
String refs are projections, not authority.
```

The database should express relationships using columns such as:

```text
comic_id
chapter_id
local_library_item_id
provider_id
remote_work_id
page_index
source_kind
```

The runtime should pass typed objects such as `ReaderOpenTarget`, not parse one
magic string to recover authority.

## Diagnostics Direction

Diagnostics should answer decision questions, not merely record that something
happened.

Important runtime diagnostics should include:

- identity
- authority
- lifecycle phase
- route/request correlation
- entrypoint/caller where relevant
- rejection reason when a boundary blocks invalid state

Preferred diagnostic shape:

```text
event=reader.route.unresolved_target
comic.id=<comicId>
source.kind=local
chapter.id=null
reason=missing_local_chapter
boundary=route.dispatch
action=rejected
```

Diagnostics should report violations. They should not repair state or downgrade
invalid runtime identity into harmless-looking pending state.

## Current Feature Scope

Existing and intended capabilities include:

- read local comics
- read comics from network sources
- manage favorite comics
- download comics
- use JavaScript-based comic sources
- view comments, tags, and metadata if a source supports them
- login to perform source-specific operations if a source supports them

Feature availability may change while the architecture is being restructured.

## Build From Source

1. Clone the repository.
2. Install [Flutter](https://flutter.dev/).
3. Install [Rust](https://rustup.rs/).
4. Build for your platform, for example:

```bash
flutter build apk
```

## Release Channels

Official release channels for this fork are limited to this repository's GitHub
Releases unless stated otherwise.

AUR, F-Droid, or other third-party packages may still point to the abandoned
upstream project and are not maintained by this fork.

## Contributing

Before opening an issue or pull request, read
[Contribution And Issue Policy](./CONTRIBUTING.md).

This repository is not a feature request queue.

Issues must be actionable and include:

- reproduction steps
- logs or diagnostics where relevant
- affected platform/version
- expected behavior
- actual behavior
- concrete proposal where relevant

Low-effort wishlist issues may be closed without implementation.

Because this fork intentionally allows breaking changes, proposals that depend
on preserving the old fragmented storage model may be rejected unless they
include a clear migration path and do not block the new canonical data model.

## Architecture Notes

See also:

- [Ownership Lessons From Reader Debugging](./docs/tech-notes/routing-model-storage-diagnostics-ownership.md)
- [Comic Source](./doc/comic_source.md)
- [Headless Doc](./doc/headless_doc.md)
- [Debug Diagnostics API](./doc/debug_api.md)

## 中文說明

### Fork 狀態

此 fork 不是保守維護版。

上游 repository 已 archived / read-only，並不再被視為此 fork 的架構權威。
此 fork 由 `mythic3011` 以 best-effort 方式維護，優先服務個人使用流程，
不提供保證式支援，亦不保證與舊有 fragmented runtime/storage 設計保持相容。

### 重構方向

目前方向不是單純修補幾個 bug，而是把有用行為從 legacy code 中抽出，重新建立
清晰的 runtime、database、model、repository、routing、diagnostics ownership。

基本原則是：

- UI 只表達 user intent
- application/use-case layer 協調流程
- domain model 定義 identity 與規則
- repository 負責讀寫 canonical storage
- database layer 負責 schema、migration、transaction
- runtime layer 負責 reader/source execution
- diagnostics 負責記錄 evidence，不負責修補 state
- legacy code 不應擁有 live runtime authority

### Data compatibility

此 fork 可能會引入 local data storage breaking changes。

舊有 `local.db`、`history.db`、`local_favorite.db`、`implicitData.json` 等資料面，
只會被視為 optional import source，不會被視為永久 runtime contract。

之後可能會：

- 建立新的 canonical database
- 停止寫入舊 DB files
- 只提供 best-effort 舊資料匯入
- 移除舊 compatibility path
- 在舊格式不安全或不一致時重建 local metadata

### Reader runtime

Reader 正朝向 canonical-only runtime path。

舊 reader UI / routing path 如果仍然會建立、修補或推斷 runtime identity，就會被視為
untrusted。正確方向是 UI 只傳 intent，由 resolver 建立 resolved ReaderOpenTarget，
runtime 只接收 validated ReaderOpenRequest。

舊流程中這類模式不應繼續留在 live runtime：

```text
UI builds SourceRef
  -> route accepts incomplete identity
  -> ReaderWithLoading repairs chapter
  -> legacy resume fallback reads appdata
  -> session repairs active tab
  -> diagnostics hides invalid state
```

未 resolved 的 reader target 不應再用 `local:local:<comicId>:_` 這類 placeholder ID 表達。
應改為 typed failure + structured diagnostics。

### 貢獻說明

開 issue 或 PR 前，請先閱讀 [Contribution And Issue Policy](./CONTRIBUTING.md)。

本 repo 不是許願池。Issue 必須可執行，bug 回報需要包含重現步驟、log / diagnostics、
受影響平台與版本；功能建議需要提供具體行為、設計方向與相關風險。

由於此 fork 明確允許 breaking changes，若提案依賴保留舊有 fragmented storage model，
除非同時提供清楚 migration path，且不阻礙新的 canonical data model，否則可能會被拒絕。

## Thanks

### Tags Translation

[EhTagTranslation](https://github.com/EhTagTranslation/Database)

The Chinese translation of the manga tags is from this project.
