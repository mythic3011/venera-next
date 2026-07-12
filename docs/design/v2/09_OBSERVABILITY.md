# Observability: Diagnostics Events

**Current diagnostics event contract and persisted evidence shape for runtime/core.**

> Observability has three distinct surfaces — do not mix them:
> 1. **Diagnostics events** (this file) — bounded local/dev evidence in the runtime DB; best-effort writes.
> 2. **Logs** — OTel Log Data Model only, pre-approved attribute keys, privacy tiers; see `06_SECURITY_AUTH_RECOMMENDATION.md`.
> 3. **Audit events** — tamper-evident, append-only, hash-chained; see `06_SECURITY_AUTH_RECOMMENDATION.md` + schema in `02_DATABASE_SCHEMA.md`.
> Privacy TIER 0/1/2 rules apply to all three.

---

## Overview

Diagnostics events are emitted by use cases and domain operations. They serve:
- **Evidence**: what happened and when
- **Debugging**: trace flow via correlation IDs
- **Operational troubleshooting**: surface warnings, validation failures, and boundary problems

Events are **immutable** once recorded. Stored and replayed diagnostics events preserve an explicit versioned public shape; for the current runtime/core foundation slice, persisted events read back with `schemaVersion = "1.0.0"`.

Current canonical scope is bounded diagnostics evidence for local/dev and short-lived runtime troubleshooting. This document does not authorize an unbounded production log store in the main runtime database.

> [!WARNING]
> Diagnostics are evidence, not repair logic. Events must never mutate runtime state or become hidden authority.

Schema evolution policy:
- Additive optional payload fields are allowed within the same major `schemaVersion`.
- Readers must ignore unknown payload fields.
- Renaming, removing, or changing the meaning/type of existing fields requires a major `schemaVersion` bump.
- Producers must keep emitting the older shape until all in-scope readers have an explicit compatibility path.

---

## Event Entity

```
Entity: DiagnosticsEvent
  id: String (UUID v4, globally unique)
  schemaVersion: String (required, "1.0.0")
  timestamp: Timestamp (UTC, ISO8601)

  level: String ("trace" | "info" | "warn" | "error")
  channel: String (diagnostic namespace, e.g. "reader.route")
  eventName: String (namespaced event name, e.g. "reader.route.unresolved_target")

  correlationId: String (optional, trace ID)
  boundary: String (optional)
  action: String (optional)
  authority: String (optional, "canonical_db" | "storage" | "source_runtime" | "unknown")

  contentId: String (optional)
  sourcePlatformId: String (optional)

  payload: Object (sanitized event payload)
```

Adapter-specific request metadata such as pseudonymous user identifiers, session identifiers, coarse environment labels, or query previews are not top-level canonical persisted fields in the current core slice. If needed, they must be encoded into sanitized payload fields deliberately.

---

## Event Name Families

The names below are naming guidance and current/future examples, not proof that every event is already emitted by the implementation.

### Content Domain Events

#### content.created
**When**: New content added to library
**Level**: info

#### content.updated
**When**: Content metadata modified
**Level**: info

#### content.removed
**When**: Content hidden from default library surfaces via `libraryStatus = "removed"`
**Level**: info

#### content.deleted
**When**: Content permanently purged from database records
**Level**: warn

#### content.imported
**When**: Import flow completed
**Level**: info

#### content.relationship.detected
**When**: Recommendation/fingerprint logic proposes or records related-content evidence
**Level**: info

---

### Section Domain Events

#### sections.created
**When**: ContentSections (with units) created from an import plan
**Level**: info

#### section.units_reordered
**When**: A section's unit display order is replaced by a user-override ContentUnitOrder
**Level**: info

---

### Collection Domain Events

#### collection.created
**When**: User collection created
**Level**: info

#### collection.item_added
**When**: Content added to user collection
**Level**: info

#### collection.item_removed
**When**: Content removed from a user collection
**Level**: info

#### collection.item_moved
**When**: One content is moved within a manual collection order
**Level**: info

#### collection.reordered
**When**: User collection manual order changed
**Level**: info

---

### Source Link Domain Events

#### source_link.added
**When**: Content-level source provenance is attached to a canonical Content
**Level**: info

#### source_link.updated
**When**: Content-level source provenance lifecycle or confidence changes
**Level**: info

#### source_link.removed
**When**: Content-level source provenance is detached or hard-deleted by an explicit source-link deletion use case
**Level**: info

#### section_source_link.upserted
**When**: ContentSection-level source provenance is created or updated
**Level**: info

#### section_source_link.removed
**When**: ContentSection-level source provenance is detached or hard-deleted by an explicit section-source-link deletion use case
**Level**: info

---

### Reader Domain Events

#### reader.position_changed
**When**: Reader moves to new section/unit
**Level**: info

#### reader.position_cleared
**When**: Reader position reset
**Level**: info

#### reader.route.unresolved_target
**When**: Reader target resolution exhausts fallbacks or finds stale/invalid saved local state
**Level**: warn

---

### Search & Query Events

#### search.executed
**When**: Search query performed
**Level**: info

Payload guidance:

```json
{
  "queryHash": "string",
  "queryType": "full_text | by_id | by_field",
  "matchCount": 10,
  "limit": 50,
  "offset": 0
}
```

#### source.search_performed
**When**: Source-platform search executed
**Level**: info

Payload guidance:

```json
{
  "sourcePlatformId": "uuid",
  "queryHash": "string",
  "resultsCount": 10
}
```

#### query.performed
**When**: Repository query executed (debug-only)
**Level**: trace

---

### Download / Notification / Sync Events

#### download.queued
**When**: Download task enters the queue
**Level**: info

#### download.completed
**When**: Download task finishes all requested units successfully
**Level**: info

#### download.failed
**When**: Download task exhausts retry policy or hits a non-retryable error
**Level**: warn

#### download.cancelled
**When**: User or source-link deletion cancels a queued/active download task
**Level**: info

#### notification.created
**When**: Notification row is created for a user-visible event
**Level**: info

#### notification.read
**When**: Notification is marked read
**Level**: info

#### sync.conflict
**When**: Backup/sync merge detects conflicting local and incoming state
**Level**: warn

---

### System & Infrastructure Events

#### system.startup
**When**: Application starts
**Level**: info

#### system.shutdown
**When**: Application stops
**Level**: warn

#### system.schema_defined
**When**: Pre-stable schema definition snapshot emitted for diagnostics traceability
**Level**: warn

Example payload:

```json
{
  "schemaVersion": "string",
  "definitionDigest": "sha256",
  "stage": "pre_stable"
}
```

#### system.schema_changed
**When**: Pre-stable schema definition changed
**Level**: warn

Example payload:

```json
{
  "fromDefinitionDigest": "sha256",
  "toDefinitionDigest": "sha256",
  "schemaVersion": "string",
  "stage": "pre_stable"
}
```

Stable-stage migration events are deferred until a dedicated stable migration contract is introduced.

#### system.error_unhandled
**When**: Unhandled exception occurs
**Level**: error

---

### Security Events

#### security.permission_denied
**When**: Operation denied by adapter/auth policy
**Level**: warn

#### security.validation_failed
**When**: Input validation fails
**Level**: warn

#### security.sandbox_violation
**When**: Future source execution/sandbox access denied event
**Level**: warn

**Status**: Deferred (not current core event)

---

### Source Lifecycle Event Names

The following names align with `08_SOURCE_PACKAGE_LIFECYCLE.md` and are **future lifecycle event names, not implementation proof**:

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

Example payload shape:

```json
{
  "sourcePlatformId": "uuid",
  "packageKey": "string",
  "providerKey": "string",
  "version": "1.0.0",
  "archiveSha256": "lowercase-hex",
  "trustTier": "official | community | custom",
  "verificationTier": "official | community | custom | unverified",
  "failureStep": "string (failed events only)",
  "reasonCode": "string (failed events only)"
}
```

Source lifecycle events must not persist raw archive bytes, private keys, repository access tokens, or stack traces.

---

## Redaction And Payload Rules

- Raw query strings should not be persisted by default.
- Use `queryHash` for correlation when raw query disclosure is not justified.
- `queryHash` is salted per debug bundle/export scope; do not treat it as global identity.
- Do **not** emit any preview derived from raw query text in telemetry/logs/debug bundles — `queryHash` only. Truncation is not redaction: a preview still contains user text and violates Tier 0 (see 06).
- Raw IP address and raw user-agent should not be persisted by default.
- Error details, if included, belong inside sanitized payload fields; do not persist stack traces.

---

## Event Storage

Current persisted schema:

```
Table: diagnostics_events
  id: TEXT PRIMARY KEY (UUID)
  schema_version: TEXT NOT NULL
  timestamp: TEXT NOT NULL
  level: TEXT NOT NULL
  channel: TEXT NOT NULL
  event_name: TEXT NOT NULL
  correlation_id: TEXT (optional)
  boundary: TEXT (optional)
  action: TEXT (optional)
  authority: TEXT (optional)
  content_id: TEXT (optional)
  source_platform_id: TEXT (optional)
  payload_json: TEXT NOT NULL
```

Current indexes:

- PRIMARY KEY `id`
- INDEX on `timestamp`
- INDEX on `(level, timestamp)`
- INDEX on `correlation_id`
- INDEX on `event_name`

Current storage/retention scope:

- No server-backed retention, partitioning, or external-log-store policy is defined in the current core slice.
- Current canonical use is bounded local/dev evidence and short-lived troubleshooting data.
- Any long-retention, archived, or high-volume production diagnostics scope requires a dedicated storage/retention authority first.

---

## Event Querying Examples

### Get all events for a content

```
SELECT * FROM diagnostics_events
WHERE content_id = :content_id
ORDER BY timestamp DESC
```

### Trace a request

```
SELECT * FROM diagnostics_events
WHERE correlation_id = :correlation_id
ORDER BY timestamp ASC
```

### Find recent error events

```
SELECT * FROM diagnostics_events
WHERE level = 'error'
  AND timestamp >= :window_start_utc
ORDER BY timestamp DESC
```

### Count events by name

```
SELECT event_name,
       COUNT(*) AS count,
       MIN(timestamp) AS first_seen,
       MAX(timestamp) AS last_seen
FROM diagnostics_events
WHERE timestamp >= :window_start_utc
GROUP BY event_name
ORDER BY count DESC
```

---

## Event Consumption

Current diagnostics evidence may be consumed by:
- local/dev troubleshooting
- correlation tracing
- targeted test assertions
- bounded debug exports
