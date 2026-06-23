# Venera: Download Manager, Notifications, Content Update & Reading Stats

---

## Download Manager

### Entities

```
Entity: DownloadTask
  id:              DownloadTaskId (UUID v4)
  contentId:       ContentId
  sectionIds:      ContentSectionId[]   -- empty = all sections
  pluginKey:       String               -- which provider plugin fetches
  sourceLinkId:    SourceLinkId
  status:          Enum (queued | preflight | fetching | copying | completed | failed | cancelled | paused)
  priority:        Integer              -- lower = higher priority
  totalUnits:      Integer
  doneUnits:       Integer
  failedUnits:     Integer
  errorCode:       String?
  errorMessage:    String?
  retryCount:      Integer
  maxRetries:      Integer (default 3)
  targetBackendKey: String              -- which storage backend
  wifiOnly:        Boolean              -- wait for WiFi
  bytesTotal:      Integer?
  bytesDone:       Integer?
  startedAt:       Timestamp?
  completedAt:     Timestamp?
  createdAt:       Timestamp
  updatedAt:       Timestamp

Entity: DownloadQueue (singleton config)
  id:              "singleton"
  maxConcurrent:   Integer (default 3)
  wifiOnlyDefault: Boolean
  autoDeleteAfterRead: Boolean
  updatedAt:       Timestamp
```

```sql
CREATE TABLE download_tasks (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  section_ids_json  TEXT NOT NULL DEFAULT '[]',
  plugin_key        TEXT NOT NULL,
  source_link_id    TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
  status            TEXT NOT NULL DEFAULT 'queued' CHECK (status IN (
    'queued','preflight','fetching','copying','completed','failed','cancelled','paused'
  )),
  priority          INTEGER NOT NULL DEFAULT 100,
  total_units       INTEGER NOT NULL DEFAULT 0,
  done_units        INTEGER NOT NULL DEFAULT 0,
  failed_units      INTEGER NOT NULL DEFAULT 0,
  error_code        TEXT,
  error_message     TEXT,
  retry_count       INTEGER NOT NULL DEFAULT 0,
  max_retries       INTEGER NOT NULL DEFAULT 3,
  target_backend_key TEXT NOT NULL,
  wifi_only         INTEGER NOT NULL DEFAULT 0,
  bytes_total       INTEGER,
  bytes_done        INTEGER,
  started_at        TEXT,
  completed_at      TEXT,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL
);
CREATE INDEX idx_download_tasks_status   ON download_tasks(status, priority);
CREATE INDEX idx_download_tasks_content  ON download_tasks(content_id);
```

### Use Cases

```
UC-DL-001: Enqueue Download
Input:  { contentId, sectionIds?, sourceLinkId, priority?, wifiOnly?, targetBackendKey? }
Flow:   1. Validate content + sourceLink exist
        2. Resolve sectionIds (empty = all undownloaded sections)
        3. Count units to download (totalUnits)
        4. Create DownloadTask (status: queued)
        5. Emit download.queued
        6. If queue not full and network ok → start immediately

UC-DL-002: Process Download Task (internal)
Flow:   1. status → preflight
        2. For each section → provider.getUnits(remoteSectionId)
        3. For each unit URL:
           a. provider.resolveUnitUrl(url) if needed
           b. fetch(url) with plugin proxy
           c. allocateStorageObject
           d. writePlacement (authority, synced)
           e. update ContentUnit.storageObjectId
           f. doneUnits++
        4. status → completed
        5. Emit download.completed → trigger notification

UC-DL-003: Pause / Resume Download
Input:  { taskId }
Flow:   pause → status = paused (stops fetching after current unit)
        resume → status = queued (re-enter queue)

UC-DL-004: Cancel Download
Input:  { taskId, deletePartial: Boolean }
Flow:   1. status → cancelled
        2. If deletePartial → delete downloaded StorageObjects + Placements for this task

UC-DL-005: Retry Failed Download
Input:  { taskId }
Flow:   1. Check retryCount < maxRetries
        2. Reset status → queued, retryCount++
        3. Re-enter queue

UC-DL-006: Download Queue Config
Input:  { maxConcurrent?, wifiOnly?, autoDeleteAfterRead? }
Flow:   Update DownloadQueue singleton config

UC-DL-007: Batch Download
Input:  { contentIds: ContentId[], options }
Flow:   For each contentId → UC-DL-001
        Returns List<DownloadTask>
```

### Download Policy

```typescript
const DownloadPolicy = {
  maxConcurrent:         3,     // max parallel downloads
  maxConcurrentPerPlugin: 2,    // per provider plugin
  chunkSize:             5,     // units fetched in parallel within one task
  retryDelay:            [2000, 5000, 15000],  // exponential (ms)
  wifiOnlyDefault:       false,
  bandwidth: {
    maxBytesPerSec:      0,     // 0 = unlimited
    throttleEnabled:     false,
  }
}
```

---

## Notification System

### Entities

```
Entity: Notification
  id:              NotificationId (UUID v4)
  type:            NotificationEventType
  read:            Boolean
  contentId:       ContentId?    -- associated content if any
  pluginKey:       String?       -- associated plugin if any
  titleKey:        String        -- i18n key
  bodyKey:         String        -- i18n key
  params:          JsonObject    -- interpolation params for i18n
  actionUrl:       String?       -- deep link (venera://...)
  createdAt:       Timestamp

enum NotificationEventType:
  new_sections_available   -- new chapters from update check
  download_completed
  download_failed
  plugin_update_available
  plugin_installed
  plugin_error
  library_health_issue
  import_completed
  import_failed
  sync_conflict             -- hosted mode only
  auth_session_expiring     -- hosted mode only

Entity: NotificationPreferences
  id:              "singleton"
  preferencesJson: JsonObject   -- Record<NotificationEventType, NotificationDelivery>

interface NotificationDelivery {
  inApp:   Boolean   -- show in-app badge/panel
  push:    Boolean   -- mobile push notification
  desktop: Boolean   -- desktop OS notification
  sound:   Boolean
}
```

```sql
CREATE TABLE notifications (
  id           TEXT PRIMARY KEY,
  type         TEXT NOT NULL,
  read         INTEGER NOT NULL DEFAULT 0,
  content_id   TEXT REFERENCES contents(id) ON DELETE CASCADE,
  plugin_key   TEXT,
  title_key    TEXT NOT NULL,
  body_key     TEXT NOT NULL,
  params_json  TEXT NOT NULL DEFAULT '{}',
  action_url   TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX idx_notifications_read    ON notifications(read, created_at);
CREATE INDEX idx_notifications_content ON notifications(content_id);
```

### Use Cases

```
UC-NOTIF-001: Record Notification
Input:  { type, contentId?, pluginKey?, params, actionUrl? }
Flow:   1. Create Notification row
        2. Check NotificationPreferences for delivery methods
        3. If inApp → update badge count
        4. If push → send via OS push API
        5. If desktop → show OS notification
        Emit: notification.created

UC-NOTIF-002: Mark Read
Input:  { notificationIds: NotificationId[] } | { markAllRead: true }

UC-NOTIF-003: List Notifications
Input:  { unreadOnly?: Boolean; limit?: Integer; offset?: Integer }
Output: List<Notification>, unreadCount: Integer

UC-NOTIF-004: Delete Notification
Input:  { notificationId } | { olderThan: Timestamp }

UC-NOTIF-005: Update Preferences
Input:  { preferences: Partial<Record<NotificationEventType, NotificationDelivery>> }
```

---

## Content Update / Refresh

### Entities

```
Entity: ContentUpdateSchedule
  id:              ContentUpdateScheduleId (UUID v4)
  contentId:       ContentId
  sourceLinkId:    SourceLinkId
  pluginKey:       String
  checkIntervalH:  Integer (default 24)
  lastCheckedAt:   Timestamp?
  nextCheckAt:     Timestamp
  lastFoundNewAt:  Timestamp?   -- last time new sections were found
  enabled:         Boolean
  createdAt:       Timestamp
  updatedAt:       Timestamp

Entity: ContentUpdateCheckResult
  id:              UUID v4
  scheduleId:      ContentUpdateScheduleId
  checkedAt:       Timestamp
  newSectionCount: Integer
  status:          Enum (ok | no_change | error | plugin_unavailable)
  errorCode:       String?
```

```sql
CREATE TABLE content_update_schedules (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  source_link_id    TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
  plugin_key        TEXT NOT NULL,
  check_interval_h  INTEGER NOT NULL DEFAULT 24,
  last_checked_at   TEXT,
  next_check_at     TEXT NOT NULL,
  last_found_new_at TEXT,
  enabled           INTEGER NOT NULL DEFAULT 1,
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  UNIQUE (content_id, source_link_id)
);
CREATE INDEX idx_schedules_next_check ON content_update_schedules(next_check_at, enabled);
```

### Update Check Flow

```
Background Job (runs every hour or on app foreground):
  1. SELECT * FROM content_update_schedules WHERE next_check_at <= now AND enabled = 1
  2. For each schedule (max 10 concurrent):
     a. Ensure plugin is active
     b. provider.getSections(sourceContentId)  ← via plugin
     c. Compare returned sections vs existing ContentSection rows
     d. New sections found?
        → Create ContentSection + SectionSourceLink rows
        → Update schedule.lastFoundNewAt
        → UC-NOTIF-001 { type: "new_sections_available", contentId, params: { count } }
        → If auto-download enabled → UC-DL-001
     e. Update schedule.lastCheckedAt, nextCheckAt = now + checkIntervalH
     f. Log ContentUpdateCheckResult

UC-UPD-001: Subscribe Content to Updates
Input:  { contentId, sourceLinkId, checkIntervalH? }
Flow:   Create ContentUpdateSchedule
        Set nextCheckAt = now + checkIntervalH

UC-UPD-002: Manual Refresh
Input:  { contentId }
Flow:   Find active schedules for content
        Run update check immediately (bypass nextCheckAt)

UC-UPD-003: Unsubscribe
Input:  { contentId, sourceLinkId }
Flow:   Set schedule.enabled = false
```

---

## Reading Statistics

Separate from ReadingSession (position) — this is analytics.

### Entities

```
Entity: ReadingStatEntry
  id:              UUID v4
  contentId:       ContentId
  sectionId:       ContentSectionId?
  sessionDate:     Date (YYYY-MM-DD, local timezone)
  durationSec:     Integer    -- time spent reading (seconds)
  unitsRead:       Integer    -- pages/units viewed
  sessionId:       String     -- anonymous, rotates daily (privacy)
  contentType:     ContentType
  createdAt:       Timestamp

Entity: ReadingStreak
  id:              "singleton"
  currentStreak:   Integer   -- consecutive days
  longestStreak:   Integer
  lastReadDate:    Date?      -- YYYY-MM-DD
  totalDaysRead:   Integer
  updatedAt:       Timestamp
```

```sql
CREATE TABLE reading_stat_entries (
  id            TEXT PRIMARY KEY,
  content_id    TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  section_id    TEXT REFERENCES content_sections(id) ON DELETE SET NULL,
  session_date  TEXT NOT NULL,     -- YYYY-MM-DD
  duration_sec  INTEGER NOT NULL DEFAULT 0,
  units_read    INTEGER NOT NULL DEFAULT 0,
  content_type  TEXT NOT NULL,
  created_at    TEXT NOT NULL
);
CREATE INDEX idx_stats_content     ON reading_stat_entries(content_id, session_date);
CREATE INDEX idx_stats_date        ON reading_stat_entries(session_date);

CREATE TABLE reading_streak (
  id              TEXT PRIMARY KEY DEFAULT 'singleton',
  current_streak  INTEGER NOT NULL DEFAULT 0,
  longest_streak  INTEGER NOT NULL DEFAULT 0,
  last_read_date  TEXT,
  total_days_read INTEGER NOT NULL DEFAULT 0,
  updated_at      TEXT NOT NULL
);
```

### Stat Aggregations

```typescript
// Derived at query time, not stored:

interface ReadingStatSummary {
  // Totals
  totalDurationSec:    number
  totalUnitsRead:      number
  totalContentsRead:   number    // unique contentIds with completionRate > 0.9

  // Time-based
  dailyAverageSec:     number
  weeklyTrend:         DailyStats[]   // last 7 days

  // Per content type
  byContentType:       Record<ContentType, { count: number; durationSec: number }>

  // Streaks
  currentStreak:       number
  longestStreak:       number

  // Top content
  mostReadContent:     Array<{ contentId: string; durationSec: number }>
}

// UC-STAT-001: Record Reading Session
// Called when user exits reader or after reading > 30s
// Input: { contentId, sectionId, durationSec, unitsRead }
// Always async, never blocks reader

// UC-STAT-002: Get Reading Summary
// Input: { fromDate?, toDate?, contentType? }
// Output: ReadingStatSummary

// UC-STAT-003: Get Content Stats
// Input: { contentId }
// Output: { totalDurationSec, unitsRead, lastReadAt, completionRate }
```

---

## Search Architecture (Full Design)

### Search Index

```typescript
// SQLite FTS5 for text content
// Vector search for semantic (sqlite-vec / pgvector)
// Tag index for faceted search

// Search query language:
// "chainsaw man" → keyword search
// tag:action → tag filter
// type:comic → content type filter
// status:completed → status filter
// rating:>=4 → rating filter
// author:"fujimoto" → author search
// lang:ja → language filter
// added:>7d → added within 7 days
// (chainsaw OR "csm") AND tag:action → boolean operators
```

```sql
-- Full-text search index (text content types only)
CREATE VIRTUAL TABLE content_fts USING fts5(
  content_id  UNINDEXED,
  unit_id     UNINDEXED,
  text_content,
  tokenize = "unicode61"
);

-- Title search index (all content)
CREATE VIRTUAL TABLE content_title_fts USING fts5(
  content_id  UNINDEXED,
  title,
  normalized_title,
  tokenize = "unicode61"
);
```

### Search Use Cases

```
UC-SEARCH-001: Basic Search
Input:  { query: String; filters?: SearchFilter; sort?: SearchSort; limit?; offset? }
Flow:
  1. Parse query string → extract keyword + filters
  2. Expand Chinese variants (zh-HK ↔ zh-CN via OpenCC)
  3. Parallel execution:
     a. FTS5 keyword search on title + normalized_title
     b. Vector semantic search (if embedding available)
     c. Tag filter (canonical tags)
     d. Metadata filters (type, status, rating, date)
  4. Merge + deduplicate results
  5. Rank: FTS rank * 0.5 + semantic similarity * 0.3 + recency * 0.2
  6. Apply library_status filter (exclude removed unless requested)
  7. Return paginated SearchResult[]

interface SearchFilter {
  contentTypes?:  ContentType[]
  tags?:          CanonicalTagKey[]
  rating?:        { gte?: number; lte?: number }
  status?:        string[]
  language?:      string[]
  addedAfter?:    Timestamp
  addedBefore?:   Timestamp
  hasSourceLink?: Boolean
  includeRemoved?: Boolean
}

UC-SEARCH-002: Save Search
Input:  { query, filters, name }
Output: SavedSearch entity

UC-SEARCH-003: Search Suggestions / Autocomplete
Input:  { prefix: String; limit?: Integer }
Flow:   1. Match against canonical tag labels (zh-HK + en)
        2. Match against recent search history
        3. Match against content titles (prefix)
        Output: List<{ text: String; type: "tag" | "history" | "title" }>

UC-SEARCH-004: Search History
  Record: log search queries as query_hash (not raw query, privacy)
  List: return recent search history
  Clear: delete search history
```

```sql
CREATE TABLE saved_searches (
  id           TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  query_text   TEXT NOT NULL,
  filters_json TEXT NOT NULL DEFAULT '{}',
  sort_json    TEXT NOT NULL DEFAULT '{}',
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE search_history (
  id           TEXT PRIMARY KEY,
  query_hash   TEXT NOT NULL,    -- one-way hash of query (PRIVACY)
  query_preview TEXT,            -- short sanitized preview for display
  result_count INTEGER,
  searched_at  TEXT NOT NULL
);
CREATE INDEX idx_search_history_date ON search_history(searched_at DESC);
```

---

## Sync / Backup

### Library Backup

```
UC-BACKUP-001: Export Library Backup
Output: ZIP file containing:
  venera-backup.json:
    version: String
    exportedAt: String
    contents: ContentMetadata[]      -- titles, tags, ratings, NO bytes
    collections: UserCollection[]
    collectionItems: UserCollectionItem[]
    readingSessions: ReadingSession[] -- positions
    readingStats: ReadingStatEntry[]
    userTags: UserTag[]
    creatorMappings: ContentCreator[]
    relationships: ContentRelationship[]
    settings: UserReaderPreferences

  Note: NO storage bytes in backup (those are in storage backends)
  Note: NO auth data, NO credentials

UC-BACKUP-002: Restore from Backup
Input:  { backupFile, mode: "merge" | "replace" }
Flow:   merge  → add/update, don't delete existing content
        replace → full replace (DANGEROUS, requires confirmation)
        Content matched by normalizedTitle + contentType
        Reading sessions merged (latest position wins)

UC-BACKUP-003: Sync Reading Position (Hosted Mode)
Flow:   On each UpdateReaderPosition:
        If hosted + multi-client:
          1. Check session.version vs server version
          2. If conflict → emit sync.conflict notification
          3. User resolves: "Use mine" | "Use server" | "Keep both"
```

### Session Version for Conflict Detection

```sql
-- Add to reading_sessions for hosted mode
ALTER TABLE reading_sessions ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE reading_sessions ADD COLUMN device_id TEXT;  -- which device last wrote
-- On conflict: client sends { expectedVersion: N }, server rejects if N != current
```

---

## Content Filtering / Parental Controls

```
Entity: ContentFilterProfile
  id:              "singleton"
  enabled:         Boolean
  maxContentRating: Enum (all | safe | moderate | adult_only)
  blockedTags:     CanonicalTagKey[]   -- hide content with these tags
  blockedSourcePlatforms: String[]     -- hide content from these platforms
  requirePinToDisable: Boolean
  pinHash:         String?             -- argon2 hash of PIN

ContentRating enum:
  safe          -- G/PG content
  moderate      -- PG-13 / teen
  adult_only    -- M/R18 content
  explicit      -- explicit adult content
```

```sql
CREATE TABLE content_filter_profile (
  id                      TEXT PRIMARY KEY DEFAULT 'singleton',
  enabled                 INTEGER NOT NULL DEFAULT 0,
  max_content_rating      TEXT NOT NULL DEFAULT 'all',
  blocked_tags_json       TEXT NOT NULL DEFAULT '[]',
  blocked_platforms_json  TEXT NOT NULL DEFAULT '[]',
  require_pin_to_disable  INTEGER NOT NULL DEFAULT 0,
  pin_hash                TEXT,
  updated_at              TEXT NOT NULL
);

-- Content rating stored on content_metadata
ALTER TABLE content_metadata ADD COLUMN content_rating TEXT
  CHECK (content_rating IN ('safe','moderate','adult_only','explicit'));
```

---

## Updated Repository Interfaces (Content-based)

All ports renamed from Comic/Chapter/Page to Content/Section/Unit.

```typescript
// CoreRepositories aggregate (complete)
interface CoreRepositories {
  // Content domain
  contents:              ContentRepositoryPort
  contentMetadata:       ContentMetadataRepositoryPort
  contentTitles:         ContentTitleRepositoryPort
  contentSections:       ContentSectionRepositoryPort
  contentUnits:          ContentUnitRepositoryPort
  contentUnitOrders:     ContentUnitOrderRepositoryPort
  readingSessions:       ReadingSessionRepositoryPort

  // Organization
  userCollections:       UserCollectionRepositoryPort
  userCollectionItems:   UserCollectionItemRepositoryPort
  smartCollections:      SmartCollectionRepositoryPort

  // Source
  sourcePlatforms:       SourcePlatformRepositoryPort
  sourceLinks:           SourceLinkRepositoryPort
  sectionSourceLinks:    SectionSourceLinkRepositoryPort

  // Creator
  creators:              CreatorRepositoryPort
  sourceCreators:        SourceCreatorRepositoryPort
  contentCreators:       ContentCreatorRepositoryPort

  // Tags
  canonicalTags:         CanonicalTagRepositoryPort
  sourceTags:            SourceTagRepositoryPort
  userTags:              UserTagRepositoryPort

  // Storage
  storageBackends:       StorageBackendRepositoryPort
  storageObjects:        StorageObjectRepositoryPort
  storagePlacements:     StoragePlacementRepositoryPort

  // Fingerprint & Recommendation
  contentFingerprints:   ContentFingerprintRepositoryPort
  contentVectors:        ContentVectorRepositoryPort
  contentRelationships:  ContentRelationshipRepositoryPort
  contentRelationshipProposals: ContentRelationshipProposalRepositoryPort
  readingEvents:         ReadingEventRepositoryPort
  recommendationFeedback: RecommendationFeedbackRepositoryPort
  trainingSignals:       TrainingSignalRepositoryPort

  // Reader
  readerSettings:        ReaderSettingsRepositoryPort
  colorPalettes:         ContentColorPaletteRepositoryPort

  // Download
  downloadTasks:         DownloadTaskRepositoryPort

  // Notifications
  notifications:         NotificationRepositoryPort

  // Update schedule
  updateSchedules:       ContentUpdateScheduleRepositoryPort

  // Stats
  readingStats:          ReadingStatRepositoryPort
  readingStreak:         ReadingStreakRepositoryPort

  // Search
  savedSearches:         SavedSearchRepositoryPort
  searchHistory:         SearchHistoryRepositoryPort

  // Plugin
  installedPlugins:      InstalledPluginRepositoryPort
  importJobs:            ImportJobRepositoryPort
  exportJobs:            ExportJobRepositoryPort
  sourceRepositories:    SourceRepositoryRepositoryPort
  packageArtifacts:      SourcePackageArtifactRepositoryPort

  // Auth (hosted mode)
  authUsers:             AuthUserRepositoryPort
  authSessions:          AuthSessionRepositoryPort
  passkeys:              PasskeyRepositoryPort
  apiKeys:               ApiKeyRepositoryPort
  oauthConnections:      OAuthConnectionRepositoryPort
  wsTickets:             WsTicketRepositoryPort

  // System
  auditEvents:           AuditEventRepositoryPort
  auditCheckpoints:      AuditCheckpointRepositoryPort
  telemetryConsent:      TelemetryConsentRepositoryPort
  operationIdempotency:  OperationIdempotencyRepositoryPort
  setupState:            SetupStateRepositoryPort
  clientNetworkConfig:   ClientNetworkConfigRepositoryPort
  contentFilterProfile:  ContentFilterProfileRepositoryPort
  diagnosticsEvents:     DiagnosticsEventRepositoryPort
}
```
