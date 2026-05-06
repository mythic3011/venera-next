# Source Package Store Contract

## Purpose

This document defines `PackageStore` as the durable authority boundary for verified source package artifacts.

`PackageStore` is the middle durable boundary in the lifecycle commit order defined by [`source-package-artifact-lifecycle.md`](./source-package-artifact-lifecycle.md):

`verified artifact -> package store commit -> source_platform mutation`

## Scope

This is a contract-only design slice. It defines behavioral requirements and failure semantics for durable artifact persistence and read surfaces.

It does not define runtime implementation details, storage engines, or TypeScript interfaces.

## Responsibilities

`PackageStore` must:

- Persist verified artifact metadata and content as durable artifact authority.
- Commit artifact state atomically, with no durable partial install state.
- Expose a read contract for installed artifact metadata required by orchestration.
- Support deterministic orphan marking and cleanup after downstream mutation failure.
- Treat `sourcePlatformId` as optional until successful `source_platform` mutation (post-activation reference only).

## Failure Semantics

- Commit failure means no durable partial install state is observable.
- If `source_platform` mutation fails after package store commit, artifact state must either be rolled back (when transaction boundaries support rollback) or transitioned to orphaned/unreferenced state and routed to deterministic cleanup.
- Orphan cleanup must be auditable through explicit state and cleanup-path signaling at contract level.
- Orphaned artifacts must not be loadable or executable as active source packages.

## State Semantics

`PackageStore` artifact state should be described behaviorally as:

```text
committed:
  verified artifact is durably stored and eligible for source_platform mutation
  sourcePlatformId may be null at this state
active:
  artifact is referenced by a successful source_platform mutation
orphaned:
  artifact was committed but downstream source_platform mutation failed
cleanup_pending:
  artifact is scheduled for deterministic cleanup
removed:
  artifact is no longer loadable or readable as installed package state
```

`PackageStore` does not need to implement these exact enum names in this slice, but future implementations must preserve these state meanings.

## Non-responsibilities

`PackageStore` must not own:

- Source identity arbitration across existing `source_platform` state.
- Integrity verification logic (owned by verifier boundary).
- Source execution, sandbox creation, or runtime loading behavior.

## Identity Boundary

- `PackageStore` may store `packageKey`, `providerKey`, `version`, and `archiveSha256` as metadata, but it must not decide whether they are compatible with an existing `source_platform`.
- Compatibility decisions belong to installer orchestration and `source_platform` mutation policy.
- Same `packageKey`, `providerKey`, and `version` with different `archiveSha256` must be treated as a conflict by orchestration, not silently overwritten by `PackageStore`.
- Missing `sourcePlatformId` during pre-activation states is expected and must not be treated as integrity failure by `PackageStore`.

## Read Contract Rule

Read surfaces must return stored artifact metadata and state only.

They must not:

- infer provider compatibility
- repair missing `source_platform` rows
- require `sourcePlatformId` before activation
- execute package code
- validate source runtime behavior
- decide taxonomy semantics
