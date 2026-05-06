# Source Package Artifact Lifecycle

## Purpose

This document defines the architecture boundary for source package artifact lifecycle before any `SourcePackageInstaller` runtime implementation begins.

This is a design-only slice. It defines authority, ordering, idempotency, rollback/cleanup expectations, and diagnostics points.

## Scope

Lifecycle flow:

`repository entry -> archive bytes -> staging -> integrity verifier -> package store -> source_platform mutation -> cleanup`

## Hard Commit Order

Required order:

`verified artifact -> package store commit -> source_platform mutation`

Rules:

- `source_platform` mutation is not allowed before verified artifact package store commit.
- Failed package store commit prevents `source_platform` mutation.
- Package-store commit must not require a pre-existing `source_platform` reference.
- `sourcePlatformId` linkage is optional until mutation succeeds and should be attached only as a post-activation reference.
- Failed `source_platform` mutation must either:
  - roll back the package store commit when transaction boundaries support rollback, or
  - mark the committed package artifact as orphaned/unreferenced for deterministic cleanup.

Package install success requires both package store commit and `source_platform` mutation to complete in the correct order.

## Boundary Ownership

- `repository client`
  - Fetches and validates repository metadata/package entries only.
  - Must not persist archive bytes or perform installation.

- `download`
  - Retrieves archive bytes.
  - Computes and normalizes archive SHA-256.
  - Must not unpack, stage, or mutate DB state.

- `staging`
  - Future temporary artifact preparation boundary.
  - Isolated from durable package store authority.

- `integrity verifier`
  - Consumes already-provided objects/files in memory.
  - Returns verified metadata only.
  - No I/O and no mutation.

- `package store`
  - Future authority for durable verified artifacts.
  - Writes only after integrity verification succeeds.
  - `PackageStore` behavior is defined separately in [`source-package-store-contract.md`](./source-package-store-contract.md).

- `source_platform mutation`
  - Occurs only after package store commit succeeds.
  - Attaches/updates `sourcePlatformId` only after successful activation.
  - Must not create dangling providers.

- `rollback / cleanup`
  - Failed install attempts remove staging artifacts.
  - Must prevent partial active provider state.

- `diagnostics events`
  - Defines lifecycle event points.
  - Does not implement event emitters in this slice.

## Existing Completed Boundary

`createSourcePackageIntegrityVerifier()` is the existing completed pure in-memory verification boundary.

## SourcePackageInstaller Guardrails

Future `SourcePackageInstaller` is orchestration only.

It may coordinate repository client, download, staging, verifier, package store, source mutation, rollback, cleanup, and diagnostics.

It must not own:

- hash rules
- `source_platform` identity rules
- source code execution
- taxonomy semantics

## Source Platform Mutation Idempotency

Define source-platform mutation idempotency by package identity:

- same `packageKey`, `providerKey`, `version`, and `archiveSha256`
  - idempotent success / no-op

- same `packageKey`, `providerKey`, `version` with different `archiveSha256`
  - integrity/identity conflict
  - must fail closed

## Diagnostics Event Categories

This slice defines lifecycle categories only:

- `source.repository.metadata.validated`
- `source.package.download.completed`
- `source.package.staging.prepared`
- `source.package.integrity.verified`
- `source.package.store.committed`
- `source.platform.mutated`
- `source.package.rollback.completed`
- `source.package.cleanup.completed`

Add `.failed` variants where useful.

## Hard Non-Goals

This document does not introduce:

- downloader implementation
- unpack implementation
- installer implementation
- filesystem writes
- source execution
- smoke harness
