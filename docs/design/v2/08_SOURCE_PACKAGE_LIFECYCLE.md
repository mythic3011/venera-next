# Source Package Lifecycle & PackageStore Contract

> This file carries forward, unchanged in substance, the two v1 authority docs
> `source-package-artifact-lifecycle.md` and `source-package-store-contract.md`.
> It is the authoritative contract behind the plugin install pipeline summarized
> in `05_PLUGIN_SYSTEM.md` — where the two disagree, THIS file wins.

# Part A — Source Package Artifact Lifecycle

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
- Activation lease renewal requires the same installer operation and activation-lease owner token that created or claimed the committed artifact; heartbeat renewal should refresh `updatedAt` at least every 2 minutes while source-platform mutation is still in flight.
- A single activation attempt should not renew indefinitely; default maximum activation window is 30 minutes unless the installer declares a narrower operation-specific ceiling.
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
  - `PackageStore` behavior is defined in Part B of this file.

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

---

# Part B — Source Package Store Contract

## Purpose

This document defines `PackageStore` as the durable authority boundary for verified source package artifacts.

`PackageStore` is the middle durable boundary in the lifecycle commit order defined by Part A of this file:

`authentic + verified artifact -> package store commit -> source_platform mutation`

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
- Persist install-time verification evidence returned by the verifier: `verificationTier`, `publisherKeyFingerprint`, and optional `signatureDigest`.
- Detect and expose stale `committed` artifacts that did not complete activation inside the activation lease.

## Failure Semantics

- Commit failure means no durable partial install state is observable.
- If `source_platform` mutation fails after package store commit, artifact state must either be rolled back (when transaction boundaries support rollback) or transitioned to orphaned/unreferenced state and routed to deterministic cleanup.
- If orchestration crashes after commit but before source-platform mutation, the artifact remains `committed` only until the activation lease expires. After that, installer recovery must either resume mutation idempotently or mark the artifact `orphaned`.
- Orphan cleanup must be auditable through explicit state and cleanup-path signaling at contract level.
- Orphaned artifacts must not be loadable or executable as active source packages.

Default lifecycle timers:

- Activation lease for `committed`: 5 minutes from commit, renewable only by installer orchestration that still owns the same operation.
- Renewal ownership is proven by an activation-lease owner token tied to the installer operation; stale or mismatched tokens must not extend the lease.
- Installer heartbeat cadence should refresh `updated_at` at least every 2 minutes while activation is in progress, with a default maximum activation window of 30 minutes.
- Orphan cleanup eligibility: 24 hours after entering `orphaned`; metadata should remain readable for audit until the artifact-retention window expires.
- Cleanup-pending lease: 15 minutes; stuck cleanup may be retried idempotently.
- Removed artifact metadata retention is deployment policy, but removed artifacts must not expose executable/readable package content.

## State Semantics

`PackageStore` artifact state should be described behaviorally as:

```text
committed:
  verified artifact is durably stored and eligible for source_platform mutation
  sourcePlatformId may be null at this state
  must not linger past activation lease without resume or orphan transition
active:
  artifact is referenced by a successful source_platform mutation
orphaned:
  artifact was committed but downstream source_platform mutation failed
  or activation lease expired before mutation completed
cleanup_pending:
  artifact is scheduled for deterministic cleanup
removed:
  artifact is no longer loadable or readable as installed package state
```

`PackageStore` does not need to implement these exact enum names in this slice, but future implementations must preserve these state meanings.

## Verification Evidence

`PackageStore` stores verification results, but does not perform signature or integrity verification itself.

Required artifact metadata:

```text
packageKey
providerKey
version
archiveSha256
verificationTier: official | community | custom | unverified
publisherKeyFingerprint: optional normalized public-key fingerprint
signatureDigest: optional normalized signature evidence digest
```

Rules:

- Only artifacts with `verificationTier = official`, `community`, or approved `custom` may become `active`.
- `verificationTier = unverified` may be retained only as failed/audit evidence and must not be loadable or executable.
- `verificationTier = official` requires verifier evidence for a trusted official key.
- `verificationTier = community` requires verifier evidence for an accepted publisher key.
- `verificationTier = custom` requires explicit advanced-user approval before activation.

## Non-responsibilities

`PackageStore` must not own:

- Source identity arbitration across existing `source_platform` state.
- Integrity verification logic (owned by verifier boundary).
- Signature trust validation (owned by verifier/trust-policy boundary).
- Source execution, sandbox creation, or runtime loading behavior.

## Identity Boundary

- `PackageStore` may store `packageKey`, `providerKey`, `version`, and `archiveSha256` as metadata, but it must not decide whether they are compatible with an existing `source_platform`.
- Compatibility decisions belong to installer orchestration and `source_platform` mutation policy.
- Same `packageKey`, `providerKey`, and `version` with different `archiveSha256` must be treated as a conflict by orchestration, not silently overwritten by `PackageStore`.
- Missing `sourcePlatformId` during pre-activation states is expected and must not be treated as integrity failure by `PackageStore`.
- A matching package identity with different `verificationTier` or publisher fingerprint is a trust-policy conflict for orchestration; PackageStore must not silently upgrade/downgrade trust evidence.

## Read Contract Rule

Read surfaces must return stored artifact metadata and state only.

They must not:

- infer provider compatibility
- repair missing `source_platform` rows
- require `sourcePlatformId` before activation
- execute package code
- validate source runtime behavior
- decide taxonomy semantics

Read surfaces must expose enough state for recovery:

- stale committed artifacts needing resume/orphan handling
- orphaned artifacts eligible for cleanup
- cleanup_pending artifacts whose cleanup lease expired
