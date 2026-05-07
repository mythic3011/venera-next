# Runtime Design Summary (Canonical V1 Index)

**Status**: Active Canonical Index for V1 TypeScript-first runtime contracts.

---

## Scope

This file is an index and navigation aid only.
It does not define transport-specific implementation assumptions.

Adapter transport (UI/HTTP/CLI/IPC) is replaceable and non-authoritative compared to runtime/core contracts.

---

## Canonical Authority Documents

- `docs/design/entities.md`
- `docs/design/database-schema.md`
- `docs/design/repository-interfaces.md`
- `docs/design/production-database-adapter-strategy.md`
- `docs/design/use-cases.md`
- `docs/design/diagnostics-events.md`
- `docs/design/source-package-artifact-lifecycle.md`
- `docs/design/source-package-store-contract.md`

Runtime implementation authority:
- `runtime/core/src/**`

---

## Current V1 Rules

```text
normalizedTitle is non-unique matching/search signal.
ComicTitle is the canonical title-record authority surface (primary/source/alias).
CreateCanonicalComic does not create ReaderSession.
ReaderSession is at most one active session per comic.
chapterNumber is an optional ordering hint, not chapter identity authority.
Adapters send intent; application use cases own workflow.
Domain identity does not depend on protobuf/UI/file-path models.
Raw filesystem paths are not canonical storage authority.
Remote source identity/provenance goes through source links.
Tags are taxonomy/mapping-based, not loose genre string lists.
Diagnostics events are schema-versioned evidence.
```

---

## Legacy/Deprecated Documents

The following files are preserved for forensic reference and are not canonical V1 authority:

- `docs/design/ipc-protocol-api.md`
- `docs/design/class-definitions-casting.md`
- `docs/design/security-boundaries-layering.md`

If these legacy drafts conflict with canonical docs, canonical docs win.
