# Legacy Security Boundaries & Layering Draft

**Status**: Deprecated / Legacy Forensic Reference Only

> [!WARNING]
> This document contains legacy Flutter/Dart + Protobuf/gRPC + Rust-era layering assumptions.
> It is not canonical V1 runtime authority.

---

## Canonical Replacement

Use these documents as current authority instead:

- `docs/design/entities.md`
- `docs/design/database-schema.md`
- `docs/design/repository-interfaces.md`
- `docs/design/use-cases.md`
- `docs/design/diagnostics-events.md`
- `docs/design/source-package-artifact-lifecycle.md`
- `docs/design/source-package-store-contract.md`
- `runtime/core/src/**`

---

## V1 Boundary Rules (Canonical Direction)

```text
Adapters (UI/HTTP/CLI/IPC) send intent; application use cases own workflow orchestration.
Domain entities own business identity and invariants.
Repository ports return Result<T, CoreError>-shaped outcomes.
Database rows and adapter payloads must not cross into domain/application as authority.
normalizedTitle is non-unique matching/search signal, not identity uniqueness.
Source provenance is represented via source-link boundaries.
Raw filesystem paths are not canonical storage authority.
Diagnostics are evidence, not repair logic.
```

---

## Deprecation Notes

Do not use this legacy draft as authority for:
- Protobuf/gRPC transport validation as mandatory runtime boundary
- Flutter/Rust-specific layer ownership assumptions
- Duplicate-title uniqueness rules via normalizedTitle
- Local cache path fields as canonical entity/storage authority
- Source manifest as installed package authority

Keep this file only for historical comparison.
