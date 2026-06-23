# Source Package Artifact Lifecycle

## Purpose

This document defines the architecture boundary for source package artifact lifecycle before any `SourcePackageInstaller` runtime implementation begins.

This is a design-only slice. It defines authority, ordering, idempotency, rollback/cleanup expectations, and diagnostics points.

## Scope

Current contract flow:

`repository entry -> archive bytes -> authenticity + integrity verifier -> package store -> source_platform mutation -> cleanup`

Future staged-preparation flow:

`repository entry -> archive bytes -> staging -> integrity verifier -> package store -> source_platform mutation -> cleanup`

`staging` is intentionally future/optional in this contract. Current implementation may pass in-memory downloaded archive bytes directly to the verifier, provided no durable package-store commit or `source_platform` mutation occurs before authenticity and integrity verification succeeds.

## Hard Commit Order

Required order:

`authentic + verified artifact -> package store commit -> source_platform mutation`

Rules:

- `source_platform` mutation is not allowed before authentic verified artifact package store commit.
- Failed package store commit prevents `source_platform` mutation.
- Package-store commit must not require a pre-existing `source_platform` reference.
- `sourcePlatformId` linkage is optional until mutation succeeds and should be attached only as a post-activation reference.
- Failed `source_platform` mutation must either:
  - roll back the package store commit when transaction boundaries support rollback, or
  - mark the committed package artifact as orphaned/unreferenced for deterministic cleanup.
- A committed artifact that does not reach `active` before the activation lease expires must be detected as stuck and either resumed by the installer or transitioned to `orphaned`.

Package install success requires both package store commit and `source_platform` mutation to complete in the correct order.

Default lifecycle timers:

- Activation lease for `committed -> active`: 5 minutes from package-store commit unless a shorter operation-specific lease is declared.
- Orphan cleanup eligibility: 24 hours after entering `orphaned`, retaining metadata for audit while allowing byte cleanup.
- Cleanup-pending lease: 15 minutes; if cleanup starts but does not complete within the lease, cleanup may be retried idempotently.

## Boundary Ownership

- `repository client`
  - Fetches and validates repository metadata/package entries only.
  - Must not persist archive bytes or perform installation.

- `download`
  - Retrieves archive bytes.
  - Computes and normalizes archive SHA-256.
  - Must not unpack, stage, or mutate DB state.
  - Interrupted downloads may restart from scratch.
  - Byte-range resume is allowed only when the transport/source supports range validation and the final archive hash/signature verification still succeeds.
  - Partial archive bytes are never committed to PackageStore or treated as verified artifact state.

- `staging`
  - Future temporary artifact preparation boundary.
  - Isolated from durable package store authority.
  - Not required by the current contract flow.
  - If implemented later, staging artifacts must be removed on failure and must not become durable install authority.

- `integrity verifier`
  - Owns both authenticity and integrity verification.
  - Consumes already-provided objects/files in memory in the current flow, or staged objects in the future flow.
  - Verifies archive SHA-256 and manifest/archive consistency.
  - Verifies package signatures against the applicable trust tier before returning success.
  - Returns verified metadata and install-time `verificationTier` only.
  - No I/O and no mutation.

- `package store`
  - Contract authority for durable verified artifacts; runtime implementation may lag this design slice.
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

`createSourcePackageIntegrityVerifier()` is the existing completed pure in-memory verification boundary for hash/manifest consistency. Signature/authenticity verification is a required contract gap before source package install can be claimed production-safe.

## Trust Tier Model

Trust tier keeps one-button install usable while preserving publisher-side audit/scanning expectations.

```text
official:
  repository-declared trust tier
  valid signature by an official trusted key
  end-user surface: Install, Verified

community:
  repository-declared trust tier
  valid publisher signature by an accepted community key
  automated checks may run publisher-side or repository-side
  end-user surface: Install, Community

custom:
  custom repository, self-signed package, or manually supplied package
  valid custom signature when available
  requires advanced-user confirmation before activation
  end-user surface: Install (Advanced)

unverified:
  missing/invalid signature or unresolved trust root
  not eligible for one-button install or automatic activation
```

Manifest metadata:

- `trustTier: official | community | custom`
- `publisherKeyFingerprint: String (optional for custom, required for official/community)`

Artifact verification result:

- `verificationTier: official | community | custom | unverified`
- `publisherKeyFingerprint: String (optional)`
- `signatureDigest: String (optional, normalized signature evidence digest)`

`signatureValid` is resolved at install time and must not be stored as a mutable authority boolean. Persist the resulting `verificationTier` and normalized signature evidence instead.

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

Every step has success and failure diagnostics event names. Failure variants are required for install audit trails and self-host troubleshooting.

- `source.repository.metadata.validated`
- `source.repository.metadata.validation_failed`
- `source.package.download.completed`
- `source.package.download.failed`
- `source.package.staging.prepared`
- `source.package.staging.failed`
- `source.package.integrity.verified`
- `source.package.integrity.failed`
- `source.package.signature.verified`
- `source.package.signature.failed`
- `source.package.store.committed`
- `source.package.store.commit_failed`
- `source.package.store.stuck_committed`
- `source.platform.mutated`
- `source.platform.mutation_failed`
- `source.package.rollback.completed`
- `source.package.rollback.failed`
- `source.package.cleanup.completed`
- `source.package.cleanup.failed`

Event payloads must include sanitized package identity (`packageKey`, `providerKey`, `version`, `archiveSha256`), trust/verification tier when known, and failure step/reason code. They must not include raw archive bytes, private keys, tokens, or stack traces.

## Hard Non-Goals

This document does not introduce:

- downloader implementation
- unpack implementation
- installer implementation
- filesystem writes
- source execution
- smoke harness
