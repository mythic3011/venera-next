# Source Package Store Contract

## Purpose

This document defines `PackageStore` as the durable authority boundary for verified source package artifacts.

`PackageStore` is the middle durable boundary in the lifecycle commit order defined by [`source-package-artifact-lifecycle.md`](./source-package-artifact-lifecycle.md):

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
