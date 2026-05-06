# Diagnostics Events Specification

**Language-agnostic event schema for system instrumentation and audit trail.**

---

## Overview

Diagnostics events are emitted by use cases and domain operations. They serve:
- **Audit trail**: what happened and when
- **Monitoring**: track health and performance
- **Debugging**: trace flow via correlation IDs
- **Analytics**: aggregate operational behavior

Events are **immutable** once created and stored in a log/event store. Stored and replayed diagnostics events preserve an explicit versioned public shape; for the current runtime/core foundation slice, persisted events read back with `schemaVersion = "1.0.0"`.

> [!WARNING]
> Diagnostics are evidence, not repair logic. Events must never mutate runtime state or become hidden authority.

---

## Event Entity

```
Entity: DiagnosticsEvent
  id: String (UUID v4, globally unique)
  schemaVersion: String (required, "1.0.0")
  timestamp: Timestamp (UTC, ISO8601)
  correlationId: String (UUID v4, trace ID)
  sessionId: String (optional)
  userId: String (optional, adapter-provided attribution only)

  eventType: String (namespaced, e.g., "comic.created")
  category: String (comic, reader, favorite, source, import, system, security, search)
  severity: String (info, warning, error, critical)

  resourceType: String (optional)
  resourceId: String (optional)
  action: String (optional)

  payload: Object (event-specific data, no raw PII)
  metadata: Object (sanitized context only)

  duration: Integer (optional, milliseconds)
  success: Boolean
  error: Object (optional, sanitized)
```

---

## Event Categories & Types

### Comic Domain Events

#### comic.created
**When**: New comic added to library
**Severity**: info

#### comic.updated
**When**: Comic metadata modified
**Severity**: info

#### comic.deleted
**When**: Comic removed from library
**Severity**: warning

#### comic.imported
**When**: Import flow completed
**Severity**: info

---

### Reader Domain Events

#### reader.position_changed
**When**: Reader moves to new chapter/page
**Severity**: info

#### reader.position_cleared
**When**: Reader position reset
**Severity**: info

---

### Source Lifecycle Event Names

The following names align with `source-package-artifact-lifecycle.md` and are **future lifecycle event names, not implementation proof**:

- `source.repository.metadata.validated`
- `source.package.download.completed`
- `source.package.staging.prepared`
- `source.package.integrity.verified`
- `source.package.store.committed`
- `source.platform.mutated`
- `source.package.rollback.completed`
- `source.package.cleanup.completed`

Example payload shape for source lifecycle events:

```json
{
  "sourcePlatformId": "uuid",
  "packageKey": "string",
  "providerKey": "string",
  "version": "1.0.0",
  "archiveSha256": "lowercase-hex",
  "success": true
}
```

---

### Search & Query Events

#### search.executed
**When**: Search query performed
**Severity**: info

Payload guidance:

```json
{
  "queryHash": "string",
  "sanitizedPreview": "string (optional, truncated)",
  "queryType": "full_text | by_id | by_field",
  "matchCount": 10,
  "limit": 50,
  "offset": 0,
  "duration": 500
}
```

#### source.search_performed
**When**: Source-platform search executed
**Severity**: info

Payload guidance:

```json
{
  "sourcePlatformId": "uuid",
  "queryHash": "string",
  "sanitizedPreview": "string (optional, truncated)",
  "resultsCount": 10,
  "duration": 2000,
  "success": true
}
```

#### query.performed
**When**: Repository query executed (debug-only)
**Severity**: info

---

### System & Infrastructure Events

#### system.startup
**When**: Application starts
**Severity**: info

#### system.shutdown
**When**: Application stops
**Severity**: warning

#### system.schema_defined
**When**: Pre-stable schema definition snapshot emitted for diagnostics traceability
**Severity**: warning

Example payload:

```json
{
  "schemaVersion": "string",
  "definitionDigest": "sha256",
  "stage": "pre_stable",
  "success": true
}
```

#### system.schema_changed
**When**: Pre-stable schema definition changed
**Severity**: warning

Example payload:

```json
{
  "fromDefinitionDigest": "sha256",
  "toDefinitionDigest": "sha256",
  "schemaVersion": "string",
  "stage": "pre_stable",
  "success": true
}
```

Stable-stage migration events are deferred until a dedicated stable migration contract is introduced.

#### system.error_unhandled
**When**: Unhandled exception occurs
**Severity**: critical

---

### Security Events

#### security.permission_denied
**When**: Operation denied by adapter/auth policy
**Severity**: warning

#### security.validation_failed
**When**: Input validation fails
**Severity**: warning

#### security.sandbox_violation
**When**: Future source execution/sandbox access denied event
**Severity**: warning

**Status**: Deferred (not current core event)

---

## Redaction And Hashing Policy

- Raw query strings should not be persisted by default.
- Use `queryHash` for correlation.
- `queryHash` is salted per debug bundle/export scope.
- The same query may produce different hashes across different exported bundles.
- Do not use `queryHash` as global identity.
- `sanitizedPreview` is optional and should be truncated.
- Raw IP address and raw user-agent should not be persisted by default.

---

## Event Metadata

`correlationId` is the cross-event trace identifier. `requestId` is the per-call/request identifier carried inside metadata.

```
metadata: {
  requestId: String (UUID v4)
  userId: String (optional, pseudonymous)
  sessionId: String (optional)

  environment: String (dev | staging | prod)
  version: String (app version)
  schemaVersion: String (diagnostics public schema version)

  duration: Integer (optional, milliseconds)
  cpuTimeMs: Integer (optional)
  memoryUsageBytes: Integer (optional)

  userAgentFamily: String (optional, coarse-grained)
  ipPrefix: String (optional, masked)
  locale: String (optional)
  timezone: String (optional)

  source: String (ui | api | daemon | import)
}
```

---

## Event Storage

### Schema

```
Table: diagnostics_events
  id: TEXT PRIMARY KEY (UUID)
  schema_version: TEXT NOT NULL
  timestamp: TIMESTAMP NOT NULL (indexed)
  correlation_id: TEXT NOT NULL (indexed)

  event_type: TEXT NOT NULL (indexed)
  category: TEXT NOT NULL (indexed)
  severity: TEXT NOT NULL (indexed)

  resource_type: TEXT
  resource_id: TEXT (indexed)
  action: TEXT

  payload: TEXT (JSON)
  metadata: TEXT (JSON)

  duration: INTEGER
  success: BOOLEAN
  error: TEXT (JSON, optional)
```

### Indexes

- PRIMARY KEY `id`
- INDEX on `timestamp`
- INDEX on `correlation_id`
- INDEX on `(event_type, timestamp)`
- INDEX on `(severity, timestamp)`
- INDEX on `resource_id`

### Retention

- **Development**: no retention limit
- **Staging**: 30 days
- **Production**: 90 days (archive older)

---

## Event Querying Examples (Generic)

### Get all events for a resource

```
SELECT * FROM diagnostics_events
WHERE resource_type = :resource_type
  AND resource_id = :resource_id
ORDER BY timestamp DESC
```

### Trace a request

```
SELECT * FROM diagnostics_events
WHERE correlation_id = :correlation_id
ORDER BY timestamp ASC
```

### Find recent errors

```
SELECT * FROM diagnostics_events
WHERE severity IN ('error', 'critical')
  AND timestamp >= :window_start_utc
ORDER BY timestamp DESC
```

### Performance analysis

```
SELECT event_type,
       COUNT(*) AS count,
       AVG(duration) AS avg_ms,
       MAX(duration) AS max_ms
FROM diagnostics_events
WHERE timestamp >= :window_start_utc
GROUP BY event_type
ORDER BY avg_ms DESC
```

---

## Event Consumption

Events can be consumed by:
- audit logs
- analytics
- monitoring/alerting
- correlation tracing
- tests/assertions

---

## Error Event Shape

When an operation fails, emit:

```json
{
  "success": false,
  "error": {
    "code": "STRING_CODE",
    "message": "sanitized message",
    "type": "ErrorType"
  }
}
```

Do not include stack traces in persisted events.
