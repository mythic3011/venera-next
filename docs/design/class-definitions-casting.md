# Legacy Class Definitions & Casting Rules

**Status**: Deprecated / Legacy Forensic Reference Only

> [!WARNING]
> This document is a legacy Flutter/Rust/Protobuf casting draft.
> It is not the canonical V1 runtime contract.
>
> V1 canonical runtime uses TypeScript-first core contracts:
> UI / HTTP / CLI / IPC adapters send intent into application use cases.
> Domain identity, storage references, source provenance, idempotency, and diagnostics
> are owned by `runtime/core` contracts, not by presentation or protobuf models.

---

## Current Canonical Direction

Use this document only as legacy reference.

Current authority lives in:
- `docs/design/entities.md`
- `docs/design/use-cases.md`
- `docs/design/repository-interfaces.md`
- `docs/design/database-schema.md`
- `docs/design/source-package-artifact-lifecycle.md`
- `docs/design/source-package-store-contract.md`
- `runtime/core/src/**`

Current V1 rules:

```text
normalizedTitle is non-unique matching signal.
CreateCanonicalComic does not create ReaderSession.
Adapters send intent; use cases own workflow.
Database rows do not cross application/domain boundaries.
Raw filesystem paths are not canonical storage authority.
Remote source identity goes through source links, not sourceKey@id strings.
Tags go through taxonomy/mapping contracts, not genreTags string lists.
Diagnostics events are schema-versioned.
```

---

## Deprecation Notes

Do not use this legacy draft as authority for:
- Protobuf/gRPC transport assumptions
- Flutter/Rust implementation assumptions
- Duplicate-title identity rules
- Query-side creation side effects
- Source manifest as installed package authority
- Filesystem path fields as canonical storage references

Keep this file only for historical comparison and forensic tracing.
