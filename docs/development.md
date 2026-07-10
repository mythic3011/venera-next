# Development and releases

## Workspace targets

The legacy Flutter application and the TypeScript canonical core are separate
development targets.

```text
lib/                         Flutter application
runtime/core/                TypeScript runtime core
packages/runtime-contracts/  Shared runtime contracts
apps/web/                    Web workspace
```

## Build and test

From the repository root:

```bash
flutter build apk
npm --prefix runtime/core run typecheck
npm --prefix runtime/core test
npm --prefix runtime/core run build
```

The runtime core also provides `lint` and `smoke` scripts. Use the command that
matches the slice being changed.

## Release channels

Official releases are published through this repository's GitHub Releases unless
stated otherwise. Third-party packages such as AUR or F-Droid may still refer to
the abandoned upstream project and are not maintained by this fork.

## Design documents

Read [the active v2 design index](design/SUMMARY.md) before changing architecture,
schema, package, or runtime contracts. The v2 documents define the active design;
files under `design/archive/` are historical references.
