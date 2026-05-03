# venera

> Upstream status: the original repository is no longer maintained by the
> upstream author.
>
> The upstream repository was archived by its owner and is read-only. GitHub
> documents archived repositories as read-only repositories used to indicate
> that a project is no longer actively maintained.
> Reference: [GitHub repository archiving
> documentation](https://docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories).
>
> This fork is maintained by `mythic3011` as a personal side-project fork.
> Maintenance is best-effort, personal-use first, and not a guaranteed support
> service.
>
> **Breaking-change fork notice:** this fork does **not** preserve the old
> fragmented local data / DB design as a compatibility target. The old storage
> model is considered legacy technical debt and may be removed, migrated, or
> replaced without backward-compatible guarantees.
>
> 上游狀態：原始儲存庫已由上游作者停止維護。
>
> 上游 repository 已由 owner archived，並成為 read-only。
>
> 此 fork 由 `mythic3011` 作為個人 side project 維護。維護屬
> best-effort，優先服務本人使用流程，並不提供保證式支援。
>
> **Breaking-change fork notice：**此 fork **不會**把舊有分散式 local
> data / DB 設計視為相容性目標。舊 storage model 會被視為 legacy technical
> debt，之後可能被移除、遷移或直接替換，不保證 backward compatibility。

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/mythic3011/venera)](https://github.com/mythic3011/venera/blob/master/LICENSE)
[![stars](https://img.shields.io/github/stars/mythic3011/venera?style=flat)](https://github.com/mythic3011/venera/stargazers)
[![Download](https://img.shields.io/github/v/release/mythic3011/venera)](https://github.com/mythic3011/venera/releases)

A comic reader that supports reading local and network comics.

## Fork Direction

This fork is not a conservative maintenance fork.

The current refactor direction is to simplify and replace legacy architecture
where it blocks local/remote comic management, source citation, tags, chapters,
reader sessions, page ordering, source installation, routing ownership, and
reliable debugging.

In particular, this fork does **not** intend to keep the old fragmented data
model as a permanent compatibility layer.

Legacy examples include:

```text
local.db
history.db
local_favorite.db
implicitData.json
mixed app/domain state in JSON files
platform-specific if/else source handling
scattered route helpers without a single reader navigation owner
page-local classes/models used as cross-feature contracts
legacy integer/source-key identity mapping used as runtime identity
logs that contain events but not enough decision-useful correlation data
```

The intended direction is:

- one canonical relational domain database
- source/platform resolver
- unified local/remote `ComicDetailPage(comicId)`
- local/remote shared management model
- explicit reader open contracts and centralized reader navigation ownership
- ownership-based placement for feature contracts, view models, and runtime models
- diagnostics that include identity, authority, lifecycle phase, and correlation IDs

SQLite is a small, self-contained relational database engine, which fits this
type of local app domain model better than scattering core domain state across
multiple feature-specific stores. Foreign key enforcement, WAL mode, and proper
schema ownership should be treated as part of the baseline DB design.
Reference: [SQLite official documentation](https://www.sqlite.org/docs.html).

The reader refactor also exposed a broader architectural rule used by this
fork: critical flows should have one declared owner. UI pages should express
user intent, feature modules should own request/model contracts, routing should
own navigation and route diagnostics, and storage layers should declare whether
they are canonical authority, compatibility fallback, cache, preference, or
diagnostic-only state.

See also: [Ownership Lessons From Reader Debugging](./docs/tech-notes/routing-model-storage-diagnostics-ownership.md).

### 中文說明

此 fork 不是保守維護版。

目前重構方向是：只要舊架構阻礙 local/remote comic 管理、source citation、
tags、chapters、reader sessions、page ordering、source installation、routing
ownership、debug / smoke verification，就會直接簡化、替換或移除。

此 fork 不打算長期維護舊有分散式 data model 作為 compatibility layer。

舊設計例子包括：

```text
local.db
history.db
local_favorite.db
implicitData.json
JSON 內混入 app state / domain state
針對 platform/source 的大量 if/else
routing helpers 分散，缺少單一 reader navigation owner
page-local classes/models 被其他 feature 當成 contract 使用
把 legacy int / source key 當 runtime identity
log 有事件但缺少足夠 decision/debug correlation context
```

目標方向是：

- 一個 canonical relational domain database
- source/platform resolver
- 統一 local/remote `ComicDetailPage(comicId)`
- local/remote 共用管理模型
- 明確 reader open contract 與集中式 reader navigation ownership
- 以 ownership 劃分 feature contracts、view models、runtime models 的放置位置
- diagnostics 需要包含 identity、authority、lifecycle phase 與 correlation IDs

Reader refactor 亦暴露一個更大的架構規則：critical flows 必須有明確 owner。
UI page 只應表達 user intent；feature module 應擁有 request/model contract；
routing layer 應擁有 navigation 與 route diagnostics；storage layer 必須標明
自己是 canonical authority、compatibility fallback、cache、preference，還是
diagnostic-only state。

## Data Compatibility Policy

This fork may introduce breaking changes to local data storage.

New versions may:

- create a new canonical database
- stop writing legacy DB files
- provide only best-effort import from old stores
- drop old compatibility paths
- reset or rebuild local metadata if the old format is unsafe or inconsistent

Old local data stores are treated as optional import sources only, not as a
permanent runtime contract.

A storage surface should not become authoritative just because a function can
read it. New storage-backed work should identify its domain authority before
adding reads or writes. Compatibility reads should be explicit, narrow, and
removable.

Expected future direction:

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

### 中文說明

此 fork 可能會引入 local data storage 的 breaking changes。

新版本可能會：

- 建立新的 canonical database
- 停止寫入舊 DB files
- 只提供 best-effort 舊資料匯入
- 移除舊 compatibility path
- 在舊格式不安全或不一致時重建 local metadata

舊 local data stores 只會被視為 optional import sources，不會被視為永久
runtime contract。

一個 storage surface 不應只因為某個 function 可以讀取它，就變成 runtime
authority。新增 storage-backed 功能前，必須先定義 domain authority；
compatibility reads 應保持明確、狹窄，而且日後可移除。

預期未來方向：

```text
data/venera.db         canonical domain DB
blobs/                 covers, pages, imports, cache files
plugins/comic_source/  comic source implementation files
logs/                  diagnostics and exported logs
config/                app preferences only
cookies/               optional auth/session storage
```

以下舊 domain stores 不應長期繼續作為 runtime truth：

```text
local.db
history.db
local_favorite.db
implicitData.json
```

## Features

- Read local comics
- Use JavaScript to create comic sources
- Read comics from network sources
- Manage favorite comics
- Download comics
- View comments, tags, and other information of comics if the source supports
  them
- Login to comment, rate, and perform other operations if the source supports
  them

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

此 fork 的官方 release channel 僅限本 repository 的 GitHub Releases，除非另有說明。

AUR、F-Droid 或其他第三方 package 可能仍指向已停止維護的上游專案，並不由此
fork 維護。

## Contributing

Before opening an issue or pull request, read
[Contribution And Issue Policy](./CONTRIBUTING.md).

This repository is not a feature request queue. Issues must be actionable and
include reproduction steps, logs, affected platform/version, and a concrete
proposal where relevant.

Low-effort wishlist issues may be closed without implementation.

Because this fork intentionally allows breaking changes, proposals that depend
on preserving the old fragmented storage model may be rejected unless they
include a clear migration path and do not block the new canonical data model.

開 issue 或 PR 前，請先閱讀[貢獻與 Issue 政策](./CONTRIBUTING.md)。

本 repo 不是許願池。Issue 必須可執行，bug 回報必須包含重現步驟、log、受影響平台/版本；
功能建議必須提供具體行為、設計方向與相關風險。

低成本、不可執行的許願式 issue 可能會被直接關閉，不會實作。

由於此 fork 明確允許 breaking changes，若提案依賴保留舊有分散式 storage
model，除非同時提供清楚 migration path，且不阻礙新的 canonical data
model，否則可能會被拒絕。

## Create A New Comic Source

See [Comic Source](./doc/comic_source.md).

## Headless Mode

See [Headless Doc](./doc/headless_doc.md).

## Debug Diagnostics API

See [Debug Diagnostics API](./doc/debug_api.md).

## Thanks

### Tags Translation

[EhTagTranslation](https://github.com/EhTagTranslation/Database)

The Chinese translation of the manga tags is from this project.
