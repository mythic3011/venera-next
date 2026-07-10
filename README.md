# venera-next

> [!WARNING]
> This is a breaking-change, personal-use-first fork of the archived upstream
> project. It is maintained on a best-effort basis and does not promise
> backward compatibility with the old runtime, storage, or source formats.

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![TypeScript Core](https://img.shields.io/badge/core-TypeScript-blue)](./runtime/core)
[![License](https://img.shields.io/github/license/mythic3011/venera-next)](https://github.com/mythic3011/venera-next/blob/master/LICENSE)

A comic reader and canonical comic-library runtime for local and network comics.

## Start here

- [Project direction and compatibility policy](./docs/project-direction.md)
- [Source packages and tag taxonomy](./docs/source-packages.md)
- [Reader runtime and data model](./docs/reader-runtime.md)
- [Development, builds, and release channels](./docs/development.md)
- [Contributing and issue policy](./docs/contributing.md)
- [Design documentation index](./docs/design/SUMMARY.md)
- [中文說明](./docs/README.zh-HK.md)

## Repository layout

```text
lib/                         Flutter application
runtime/core/                TypeScript canonical runtime core
packages/runtime-contracts/  Shared runtime contracts
apps/web/                    Web application workspace
docs/design/v2/              Active canonical design
docs/design/archive/         Historical design material
```

The active design authority is [`docs/design/v2/`](./docs/design/v2/). Archived
documents are retained for provenance only.

## Current scope

The project is restructuring toward a canonical runtime for local and remote
comics, source/provider identity, chapters and page ordering, reader sessions,
source installation, metadata, and diagnostics. Feature availability may change
while this work is in progress.

## Thanks

Tag translations are based on [EhTagTranslation](https://github.com/EhTagTranslation/Database).
