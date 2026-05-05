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
> old fragmented runtime/storage/source design.
>
> The V1 canonical source system is a breaking reset: raw one-file JavaScript
> source definitions are not accepted as canonical runtime input unless they are
> explicitly converted into the new repository/package contract.

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![TypeScript Core](https://img.shields.io/badge/core-TypeScript-blue)](./runtime/core)
[![Runtime Core Tests](https://img.shields.io/badge/runtime--core-tests-brightgreen)](./runtime/core)
[![Source Contract](https://img.shields.io/badge/source--contract-schema--validated-purple)](./runtime/core)
[![License](https://img.shields.io/github/license/mythic3011/venera)](https://github.com/mythic3011/venera/blob/master/LICENSE)
[![stars](https://img.shields.io/github/stars/mythic3011/venera?style=flat)](https://github.com/mythic3011/venera/stargazers)
[![Download](https://img.shields.io/github/v/release/mythic3011/venera)](https://github.com/mythic3011/venera/releases)

[![Breaking Changes](https://img.shields.io/badge/breaking--changes-allowed-orange)](#data-compatibility-policy)
[![Legacy Status](https://img.shields.io/badge/legacy-quarantined-yellow)](#legacy-quarantine-policy)

A comic reader and canonical comic-library runtime for local and network comics.

## Index

- [venera](#venera)
  - [Index](#index)
  - [Fork Direction](#fork-direction)
  - [Legacy Quarantine Policy](#legacy-quarantine-policy)
  - [Data Compatibility Policy](#data-compatibility-policy)
  - [Source Package And Taxonomy Direction](#source-package-and-taxonomy-direction)
  - [Reader Runtime Direction](#reader-runtime-direction)
  - [Database And Model Direction](#database-and-model-direction)
  - [Diagnostics Direction](#diagnostics-direction)
  - [Current Feature Scope](#current-feature-scope)
  - [Build From Source](#build-from-source)
  - [Release Channels](#release-channels)
  - [Contributing](#contributing)
  - [Architecture Notes](#architecture-notes)
  - [中文說明](#中文說明)
    - [Fork 狀態](#fork-狀態)
    - [重構方向](#重構方向)
    - [Data compatibility](#data-compatibility)
    - [Reader runtime](#reader-runtime)
    - [Source package 與 tag taxonomy](#source-package-與-tag-taxonomy)
    - [貢獻說明](#貢獻說明)
  - [Thanks](#thanks)
    - [Tags Translation](#tags-translation)

## Fork Direction

This fork is not a conservative maintenance fork.

The old codebase is treated as a legacy reference and extraction source, not as
an architecture that must be preserved. The current direction is closer to a
runtime/data-model restructure than a small refactor.

> [!NOTE]
> The legacy codebase is a reference and extraction source. It is not the
> architecture authority for new runtime work.

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
- Source packages are installed through schema-validated repository/package
  contracts.
- Tag taxonomy, mapping, and localization are data-driven JSON contracts, not
  hard-coded source-extension logic.

This fork may simplify, replace, or remove legacy architecture when it blocks:

- local/remote comic management
- source/provider identity
- source package integrity and permission boundaries
- tags and metadata
- tag taxonomy, localization, and provider tag mapping
- chapters and page ordering
- reader sessions
- source installation
- routing ownership
- database ownership
- diagnostics and debugging

## Legacy Quarantine Policy

Legacy code may remain temporarily for reference, extraction, or migration.
However, new runtime code must not depend on legacy paths as authority.

> [!CAUTION]
> Legacy code may remain in the tree, but it must not become live runtime
> authority again. New code should cross legacy boundaries only through explicit
> migration, import, or extraction paths.

Legacy compatibility surfaces under review include:

```text
local.db
history.db
local_favorite.db
implicitData.json
fragmented local databases
mixed app/domain state in JSON files
runtime identity derived from legacy IDs/source keys
legacy direct JS source definitions without repository/package manifests
source identity inferred from provider/display-name fields
hard-coded source tag translation/mapping logic
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

This fork may introduce breaking changes to local data storage and source-package storage.

> [!WARNING]
> Existing local data and source-package formats are not guaranteed to remain
> compatible. Old storage surfaces are optional import sources, not permanent
> runtime contracts.

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
plugins/comic_source/  verified source package artifacts
source_repositories/   repository indexes and package metadata cache
taxonomy/              canonical tags, localized labels, provider mappings
logs/                  diagnostics and exported logs
config/                app preferences only
cookies/               optional auth/session storage
```

## Source Package And Taxonomy Direction

The source system is moving away from raw one-file JavaScript source definitions.

> [!IMPORTANT]
> Canonical source installation accepts verified repository/package artifacts,
> not raw `source.js` files.

Canonical V1 source installation uses an APT-style package model:

```text
source repository index
  -> repository package entry
  -> downloaded built package archive
  -> integrity verification
  -> package manifest validation
  -> runtime entrypoint validation
  -> install/update mutation
  -> source_platform registration by providerKey
```

The identity rules are:

```text
providerKey = immutable runtime identity
source_platforms.canonical_key = providerKey
displayName = mutable UI label only
repository index = discovery / install / update catalogue
package manifest = runtime contract
runtime API = only extension-callable surface
built package artifact = only accepted canonical install input
legacy direct JS source = rejected unless explicitly converted
```

Source packages must be built from structured projects, not installed as god-file
scripts. A development source may contain TypeScript modules, helpers, tests, and
provider-specific mapping JSON, but the canonical install input is a verified
build artifact such as:

```text
dist/manifest.json
dist/index.min.js
dist/checksums.json
dist/package.zip
```

The runtime must verify package identity and integrity before install/update
mutation. Hash mismatch, missing runtime entrypoint, unsupported runtime API,
provider-key mismatch, or invalid taxonomy data should fail closed before file
write, runtime registration, source registry mutation, or database mutation.

> [!CAUTION]
> Source extension code is treated as constrained provider logic. It must not
> directly access filesystem, database, cookie, storage, environment, process, or
> unrestricted network APIs.

Extension code may only call the runtime-provided API surface, such as:

```text
ctx.net
ctx.parse
ctx.url
ctx.text
ctx.diagnostics
ctx.manifest
```

Extension code must not directly access filesystem APIs, database APIs, storage
adapters, cookies, environment variables, process APIs, or unrestricted network
APIs.

> [!NOTE]
> Tag taxonomy and localization are data contracts. Provider-specific tag mapping
> belongs in JSON files, not in extension code.

Tags are typed metadata, not an unstructured tag cloud. Source extensions should
return raw provider tags. Canonical tag identity, provider tag mapping, and
localized labels should be loaded from schema-validated JSON files:

```text
taxonomy/canonical-tags.json
taxonomy/labels/en.json
taxonomy/labels/zh-HK.json
taxonomy/labels/zh-TW.json
taxonomy/labels/zh-CN.json
taxonomy/mappings/<providerKey>.<locale>.json
```

Canonical tags should include namespace/facet/value-type information so search
and filter UI can distinguish genre, audience, demographic, year, format,
language, warning, author, artist, and source-specific tags.

Hard source-system rules for V1:

```text
No source_platform_aliases.
No previousProviderKeys.
No providerLineageId.
No displayName identity matching.
No automatic provider rename migration.
No raw direct JS source accepted as canonical runtime input.
No hard-coded cross-platform tag translation in source extension code.
No automatic canonical tag merge by display label.
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

> [!IMPORTANT]
> Reader UI should send intent only. Reader identity must be resolved by the
> canonical resolver before entering runtime.

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

> [!NOTE]
> Encoded string references are debug/rendered projections only. Database columns
> and typed domain objects own authority.

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

> [!TIP]
> A useful diagnostic should help eliminate a debug branch: routing, storage,
> database, source runtime, cache, UI state, or legacy fallback.

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
- use schema-validated JavaScript source packages
- validate source repository/package contracts before install/update
- support data-driven tag taxonomy, mapping, and localization contracts
- view comments, tags, and metadata if a source supports them
- login to perform source-specific operations if a source supports them

Feature availability may change while the architecture is being restructured.

## Build From Source

> [!NOTE]
> Build commands depend on the slice being worked on. The legacy Flutter app and
> the TypeScript canonical core are separate development targets.

1. Clone the repository.
2. Install the runtime needed for the slice you are working on.

For the legacy Flutter application:

```bash
flutter build apk
```

For the TypeScript canonical core:

```bash
npm --prefix runtime/core run typecheck
npm --prefix runtime/core test
npm --prefix runtime/core run build
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

> [!IMPORTANT]
> Issues must be actionable. Low-effort wishlist issues may be closed without
> implementation.

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
- [Implementation Roadmap](./docs/plans/implementation-roadmap.md)
- [Tech Stack Decision](./docs/plans/tech-stack-decision.md)
- [Comic Source](./doc/comic_source.md)
- [Headless Doc](./doc/headless_doc.md)
- [Debug Diagnostics API](./doc/debug_api.md)

## 中文說明

### Fork 狀態

此 fork 不是保守維護版。

上游 repository 已 archived / read-only，並不再被視為此 fork 的架構權威。
此 fork 由 `mythic3011` 以 best-effort 方式維護，優先服務個人使用流程，
不提供保證式支援，亦不保證與舊有 fragmented runtime/storage 設計保持相容。

> [!WARNING]
> 此 fork 會接受 breaking changes。舊 runtime、storage、source format 不會被視為永久相容目標。

### 重構方向

目前方向不是單純修補幾個 bug，而是把有用行為從 legacy code 中抽出，重新建立
清晰的 runtime、database、model、repository、routing、diagnostics ownership。

> [!NOTE]
> Legacy code 係 reference / extraction source，不係新 runtime architecture authority。

基本原則是：

- UI 只表達 user intent
- application/use-case layer 協調流程
- domain model 定義 identity 與規則
- repository 負責讀寫 canonical storage
- database layer 負責 schema、migration、transaction
- runtime layer 負責 reader/source execution
- diagnostics 負責記錄 evidence，不負責修補 state
- legacy code 不應擁有 live runtime authority
- source package 必須經 repository/package contract 與 schema validation
- tag taxonomy、mapping、localization 應由 JSON data contract 管理，不應寫死在 source extension code

### Data compatibility

此 fork 可能會引入 local data storage breaking changes。

> [!CAUTION]
> 舊資料面只會被視為 optional import source，不會被視為永久 runtime contract。

舊有 `local.db`、`history.db`、`local_favorite.db`、`implicitData.json` 等資料面，
只會被視為 optional import source，不會被視為永久 runtime contract。

之後可能會：

- 建立新的 canonical database
- 停止寫入舊 DB files
- 只提供 best-effort 舊資料匯入
- 移除舊 compatibility path
- 在舊格式不安全或不一致時重建 local metadata
- 以新的 source repository/package contract 取代舊 direct JS source format

### Reader runtime

> [!IMPORTANT]
> UI 只應傳 intent；reader identity 應由 canonical resolver 決定。

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

### Source package 與 tag taxonomy

> [!IMPORTANT]
> Canonical source install 只接受經 schema validation、integrity check、manifest contract 定義嘅 package artifact。

V1 canonical source system 會採用 APT-style repository/package model。

```text
source repository index
  -> repository package entry
  -> built package artifact
  -> manifest / integrity validation
  -> source_platform registration by providerKey
```

`providerKey` 是 runtime identity；`displayName` 只係顯示用 label。舊有 direct JS
source definition 不會被視為 canonical runtime input，除非先轉換成新的 repository/package
format。

Source extension 只應負責 provider-specific extraction logic，例如 search、detail、chapter、page
list。它不應直接讀寫 DB、filesystem、cookie store、storage adapter 或 unrestricted network API。
所有這類能力必須經 runtime-provided API 與 manifest permission 控制。

Tag mapping 同 localization 亦應使用 JSON data files：

```text
taxonomy/canonical-tags.json
taxonomy/labels/<locale>.json
taxonomy/mappings/<providerKey>.<locale>.json
```

Tag 應包含 namespace / facet / valueType，避免 genre、audience、year、language、warning、author
等不同語義全部混成一個 untyped tag cloud。

### 貢獻說明

開 issue 或 PR 前，請先閱讀 [Contribution And Issue Policy](./CONTRIBUTING.md)。

> [!IMPORTANT]
> 本 repo 不是許願池。Issue / PR 要可執行，並要提供 reproduction、diagnostics 或具體設計 proposal。

本 repo 不是許願池。Issue 必須可執行，bug 回報需要包含重現步驟、log / diagnostics、
受影響平台與版本；功能建議需要提供具體行為、設計方向與相關風險。

由於此 fork 明確允許 breaking changes，若提案依賴保留舊有 fragmented storage model，
除非同時提供清楚 migration path，且不阻礙新的 canonical data model，否則可能會被拒絕。

## Thanks

### Tags Translation

[EhTagTranslation](https://github.com/EhTagTranslation/Database)

The Chinese translation of the manga tags is from this project.
