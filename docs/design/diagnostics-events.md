# Diagnostics Events Specification

**Language-agnostic event schema for system instrumentation and audit trail.**

---

## Overview

Diagnostics events are emitted by all use cases and domain operations. They serve:
- **Audit trail**: Who did what and when
- **Monitoring**: Track system health and performance
- **Debugging**: Trace request flow via correlation IDs
- **Analytics**: Understand user behavior

Events are **immutable** once created and are stored in a time-series database or log. Stored and replayed diagnostics events preserve an explicit versioned public shape; for the current runtime/core foundation slice, persisted events read back with `schemaVersion = "1.0.0"`.

---

## Event Entity

```
Entity: DiagnosticsEvent
  id: String (UUID v4, globally unique)
  schemaVersion: String ("1.0.0")
  timestamp: Timestamp (UTC, ISO8601)
  correlationId: String (UUID v4, trace ID for request)
  sessionId: String (optional, user session or request ID)
  userId: String (optional, user identity)
  
  eventType: String (namespaced, e.g., "comic.created")
  category: String (domain category: comic, reader, favorite, source, import, system)
  severity: String (info, warning, error, critical)
  
  resourceType: String (entity affected: Comic, Chapter, Page, ReaderSession, etc.)
  resourceId: String (UUID of affected entity, optional)
  action: String (created, updated, deleted, accessed, queried)
  
  payload: Object (event-specific data, NOT containing PII)
  metadata: Object (context: IP address, user agent, device, etc.)
  
  duration: Integer (milliseconds, for performance tracking)
  success: Boolean (operation succeeded or failed)
  error: Object (if failed, error details without stack traces)
```

---

## Event Categories & Types

### Comic Domain Events

#### comic.created
**When**: New comic added to library
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "normalizedTitle": "string",
  "title": "string",
  "hasDescription": true,
  "hasAuthor": false,
  "genreTagCount": 3,
  "sourceType": "manual | import | remote"
}
```

#### comic.updated
**When**: Comic metadata modified
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "fieldsChanged": ["title", "description"],
  "oldNormalizedTitle": "string",
  "newNormalizedTitle": "string"
}
```

#### comic.deleted
**When**: Comic removed from library
**Severity**: warning
**Payload**:
```json
{
  "comicId": "uuid",
  "title": "string",
  "chapterCount": 5,
  "pageCount": 120,
  "wasFavorited": true
}
```

#### comic.imported
**When**: Comic imported from file
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "importBatchId": "uuid",
  "sourceType": "cbz | pdf | directory",
  "sourcePath": "string (sanitized, no secrets)",
  "fileCount": 150,
  "chapterCount": 12,
  "pageCount": 150,
  "duration": 5000,
  "success": true
}
```

#### comic.accessed
**When**: Comic opened for reading
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "sessionId": "uuid",
  "timeSinceLastRead": 86400000,
  "wasResumed": true
}
```

---

### Reader Domain Events

#### reader.position_changed
**When**: Reader moves to new chapter/page
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "sessionId": "uuid",
  "fromChapter": 0,
  "fromPage": 5,
  "toChapter": 1,
  "toPage": 0,
  "directionForward": true,
  "isFastNav": false
}
```

#### reader.position_cleared
**When**: Reader position reset to start
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "sessionId": "uuid",
  "wasAtChapter": 5,
  "wasAtPage": 10
}
```

#### reader.chapter_completed
**When**: Reader finishes a chapter (reaches last page)
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "chapterId": "uuid",
  "chapterNumber": 1.0,
  "pageCount": 25,
  "timeSpentSeconds": 180
}
```

#### reader.comic_completed
**When**: Reader finishes entire comic (last chapter, last page)
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "chapterCount": 12,
  "pageCount": 300,
  "timeSpentSeconds": 3600,
  "wasResuming": false
}
```

#### reader.error_invalid_position
**When**: Attempt to navigate to invalid position
**Severity**: warning
**Payload**:
```json
{
  "comicId": "uuid",
  "requestedChapter": 10,
  "requestedPage": 5,
  "maxChapter": 8,
  "reason": "chapter_not_found"
}
```

---

### Favorite Domain Events

#### favorite.marked
**When**: Comic added to favorites
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "favoriteId": "uuid",
  "title": "string",
  "wasAlreadyRead": true
}
```

#### favorite.unmarked
**When**: Comic removed from favorites
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "title": "string",
  "wasMostRecentlyRead": false
}
```

#### favorite.accessed
**When**: Favorited comic opened
**Severity**: info
**Payload**:
```json
{
  "comicId": "uuid",
  "isFavorited": true,
  "timeSinceLastAccess": 86400000
}
```

---

### Source & Import Domain Events

#### source.manifest_loaded
**When**: Source manifest validated and loaded
**Severity**: info
**Payload**:
```json
{
  "sourcePlatformId": "uuid",
  "canonicalKey": "string",
  "manifestId": "hash",
  "version": "1.0.0",
  "requiredPermissions": ["network.http", "storage.cache"],
  "isNewVersion": false
}
```

#### source.search_performed
**When**: Comic search executed on source platform
**Severity**: info
**Payload**:
```json
{
  "sourcePlatformId": "uuid",
  "searchQuery": "string (sanitized)",
  "resultsCount": 10,
  "duration": 2000,
  "success": true
}
```

#### import.batch_created
**When**: Import batch initialized
**Severity**: info
**Payload**:
```json
{
  "importBatchId": "uuid",
  "sourceType": "cbz | pdf | directory",
  "sourcePath": "string (sanitized)",
  "fileCount": 50,
  "totalSizeBytes": 1000000
}
```

#### import.batch_completed
**When**: Import batch successfully completed
**Severity**: info
**Payload**:
```json
{
  "importBatchId": "uuid",
  "comicId": "uuid",
  "chapterCount": 5,
  "pageCount": 100,
  "duration": 10000,
  "checksumsVerified": true
}
```

#### import.batch_failed
**When**: Import batch encountered error
**Severity**: error
**Payload**:
```json
{
  "importBatchId": "uuid",
  "sourceType": "string",
  "failureStage": "extraction | validation | creation",
  "errorCode": "string",
  "errorMessage": "string (sanitized, no PII)"
}
```

---

### System & Infrastructure Events

#### system.startup
**When**: Application starts
**Severity**: info
**Payload**:
```json
{
  "version": "string (semver)",
  "environment": "development | staging | production",
  "database": "sqlite | postgresql | mysql",
  "databaseVersion": "string",
  "schemaVersion": "integer",
  "uptimeSeconds": 0
}
```

#### system.shutdown
**When**: Application stops
**Severity**: warning
**Payload**:
```json
{
  "uptimeSeconds": 3600,
  "reason": "user | error | scheduled",
  "errorIfAbnormal": "string"
}
```

#### system.schema_migration
**When**: Database schema version updated
**Severity**: warning
**Payload**:
```json
{
  "fromVersion": 1,
  "toVersion": 2,
  "migration": "add_comic_metadata",
  "recordsAffected": 500,
  "duration": 5000,
  "success": true
}
```

#### system.error_unhandled
**When**: Unhandled exception occurs
**Severity**: critical
**Payload**:
```json
{
  "errorType": "string",
  "errorCode": "string",
  "message": "string (sanitized, no stack trace)",
  "correlationId": "uuid",
  "affectedResource": "string"
}
```

#### system.performance_degradation
**When**: Operation takes longer than expected
**Severity**: warning
**Payload**:
```json
{
  "operation": "comic.search",
  "expectedDurationMs": 1000,
  "actualDurationMs": 5000,
  "slowdownFactor": 5.0
}
```

---

### Search & Query Events

#### search.executed
**When**: Search query performed
**Severity**: info
**Payload**:
```json
{
  "query": "string (sanitized, no PII)",
  "queryType": "full_text | by_id | by_field",
  "matchCount": 10,
  "limit": 50,
  "offset": 0,
  "duration": 500
}
```

#### query.performed
**When**: Database query executed
**Severity**: info (only in debug mode)
**Payload**:
```json
{
  "queryType": "select | insert | update | delete",
  "table": "string",
  "duration": 100,
  "rowsAffected": 5
}
```

---

### Security & Authorization Events

#### security.permission_denied
**When**: Operation denied due to permissions
**Severity**: warning
**Payload**:
```json
{
  "userId": "string (hashed or anon)",
  "operation": "string",
  "resource": "string",
  "reason": "insufficient_permissions"
}
```

#### security.validation_failed
**When**: Input validation fails
**Severity**: warning
**Payload**:
```json
{
  "operation": "string",
  "fieldName": "string",
  "validationType": "type | range | format",
  "providedValue": "string (truncated if long)"
}
```

#### security.sandbox_violation
**When**: JS source sandbox access denied
**Severity**: warning
**Payload**:
```json
{
  "sourcePlatformId": "uuid",
  "manifestId": "hash",
  "attemptedAccess": "cookie | localStorage | network_external",
  "deniedResource": "string"
}
```

---

## Event Payload Guidelines

### What to Include
- Entity IDs (comicId, chapterId, etc.) - always
- Counts (pageCount, chapterCount) - for context
- Durations (milliseconds) - for performance tracking
- Boolean flags (success, wasResumed) - for analytics
- Relevant state before/after (for updates)
- Sanitized strings (query, path) - no PII or secrets

### What to Exclude
- Stack traces (replace with errorCode)
- PII (user names, emails, IP addresses)
- Database connection strings
- API keys or auth tokens
- Sensitive file paths (use sanitized versions)
- Raw HTML/markup

### Data Sanitization
- Truncate long strings to 200 characters
- Replace paths with sanitized versions
- Hash email addresses if must include
- Replace IP with "xxx.xxx.xxx.0"
- Remove query parameters from URLs

---

## Event Metadata

```
metadata: {
  // Request context
  requestId: String (UUID v4)
  userId: String (optional, hashed)
  sessionId: String (optional)
  
  // Runtime context
  environment: String (dev | staging | prod)
  version: String (app version)
  schemaVersion: Integer (DB schema version)
  
  // Performance context
  duration: Integer (milliseconds)
  cpuTimeMs: Integer (optional)
  memoryUsageBytes: Integer (optional)
  
  // User context
  userAgent: String (optional, sanitized)
  locale: String (e.g., "en-US")
  timezone: String (e.g., "UTC")
  
  // Source context
  source: String (ui | api | daemon | import)
}
```

---

## Event Storage

### Schema
```
Table: diagnostics_events
  id: TEXT PRIMARY KEY (UUID)
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
  error: TEXT (JSON, if failed)
```

### Indexes
- PRIMARY KEY `id`
- INDEX on `timestamp` (for time-series queries)
- INDEX on `correlation_id` (for tracing)
- INDEX on `(event_type, timestamp)`
- INDEX on `(severity, timestamp)`
- INDEX on `resource_id` (for entity history)

### Retention
- **Development**: Keep all events (no retention limit)
- **Staging**: Keep 30 days
- **Production**: Keep 90 days (archive older)

---

## Event Querying Examples

### Get all events for a comic
```
SELECT * FROM diagnostics_events
WHERE resource_type = 'Comic' AND resource_id = ?
ORDER BY timestamp DESC
```

### Trace a user request
```
SELECT * FROM diagnostics_events
WHERE correlation_id = ?
ORDER BY timestamp ASC
```

### Find errors in last 24 hours
```
SELECT * FROM diagnostics_events
WHERE severity IN ('error', 'critical')
  AND timestamp > NOW() - INTERVAL 24 HOUR
ORDER BY timestamp DESC
```

### Performance analysis
```
SELECT event_type, COUNT(*) as count, 
       AVG(duration) as avg_ms, MAX(duration) as max_ms
FROM diagnostics_events
WHERE timestamp > NOW() - INTERVAL 7 DAY
GROUP BY event_type
ORDER BY avg_ms DESC
```

---

## Event Consumption

Events can be consumed by:
- **Audit log**: Immutable append-only record
- **Analytics**: User behavior analysis
- **Monitoring/Alerting**: Real-time alerts on errors/performance
- **Tracing**: Correlation ID based request tracing
- **Testing**: Verify operations via event assertions

---

## Error Events

When an operation fails, emit event with:
```json
{
  "success": false,
  "error": {
    "code": "COMIC_NOT_FOUND",
    "message": "Comic with ID ... not found",
    "type": "NotFoundError"
  }
}
```

Do NOT include stack traces in events.
