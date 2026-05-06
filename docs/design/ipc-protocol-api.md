# Legacy IPC Protocol Draft (Deprecated)

**Status**: Deprecated / Legacy Reference Only

> [!WARNING]
> This document is a legacy Flutter/Rust IPC draft.
> It is not the canonical V1 runtime API contract.
> V1 uses TypeScript-first core contracts, adapter boundaries, source package schemas,
> and runtime/core use-case interfaces as authority.

---

## Deprecation Scope

This file preserves historical protocol assumptions from an older stack:
- Dart/Flutter frontend assumptions
- Rust backend assumptions
- Protobuf/gRPC transport binding

Those assumptions are no longer canonical for V1.

Do not use this document as implementation authority for:
- transport/protocol selection
- request/response schema design
- source package lifecycle behavior
- idempotency behavior
- diagnostics event shape/redaction policy
- identity/duplicate-title rules

---

## Canonical V1 Authority (Use These Docs Instead)

- `docs/design/use-cases.md`
- `docs/design/repository-interfaces.md`
- `docs/design/entities.md`
- `docs/design/diagnostics-events.md`
- `docs/design/source-package-artifact-lifecycle.md`
- `docs/design/source-package-store-contract.md`

Interpretation rules:
- Transport protocol is replaceable and adapter-owned.
- Adapters (UI/HTTP/IPC/CLI) send intent; use cases own workflow.
- Domain contracts own identity semantics.
- Ports/repositories own persistence abstractions.

---

## Known Legacy Mismatches (Non-Exhaustive)

This legacy draft conflicts with current canonical contracts in multiple areas:
- Binds IPC to Protobuf/gRPC and Flutter/Rust stack.
- Uses outdated create/update title duplicate semantics.
- Omits `idempotencyKey` and `IDEMPOTENCY_CONFLICT` behavior.
- Uses absolute filesystem path import inputs as if core authority.
- Uses outdated source-manifest model instead of source package lifecycle boundaries.
- Omits current diagnostics `schemaVersion` and query-hash redaction policy.

Treat all such details as historical context only.

---

## Migration Note

A future canonical adapter-facing API document may be introduced as `docs/design/adapter-api-boundary.md`.
Until then, compose adapter contracts from the canonical V1 authority docs listed above.
