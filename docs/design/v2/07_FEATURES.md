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
  sourceLinkId:    SourceLinkId?       -- required while queued/active; nullable for terminal history after SourceLink deletion
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

> **Target fragments.** All `CREATE TABLE` blocks in this doc are target-only; canonical home is `02_DATABASE_SCHEMA.md` (pending consolidation). Not independently authoritative.

```sql
CREATE TABLE download_tasks (
  id                TEXT PRIMARY KEY,
  content_id        TEXT NOT NULL REFERENCES contents(id) ON DELETE CASCADE,
  section_ids_json  TEXT NOT NULL DEFAULT '[]',
  plugin_key        TEXT NOT NULL,
  source_link_id    TEXT REFERENCES source_links(id) ON DELETE SET NULL,
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
UC-REMOTE-001: Materialize Remote Section Units
Input:  { sectionId, sectionSourceLinkId, pluginKey }
Trigger:
        - Lazy on first OpenReader access to a remote section
        - Eager during UC-DL-002 preflight before bytes are fetched
Flow:   1. Validate sectionSourceLink + parent SourceLink + SourcePlatform are active
        2. Fetch provider.getUnits(remoteSectionId) through PluginProxy
        3. For each provider unit, derive provenance evidence from
           (sectionSourceLinkId, provider order, sanitized url/hash evidence)
        4. Match existing ContentUnits by provenance evidence
        5. Append newly discovered units with fresh ContentUnitIds and unitIndex
        6. Never renumber or hard-delete existing units referenced by ReadingSession;
           stale provider evidence marks the unit stale/orphaned for later cleanup
        7. Materialized remote units start with storageObjectId = null
Output: { units: ContentUnit[], matchedCount: Integer, insertedCount: Integer, staleCount: Integer }

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
        2. For each section → UC-REMOTE-001 materializes/reconciles ContentUnits
        3. For each materialized unit with remote URL evidence:
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

### Planned / Deferred Repository Entity Stubs

The aggregate above is an implementation checklist. Ports without full DDL still
need a declared contract so implementors do not invent schemas ad hoc.

```
SmartCollection (Deferred)
  Purpose: saved dynamic collection definition over search/filter criteria.
  Authority: query/filter JSON only; membership is derived at read time.

Creator (Planned Canonical)
  Purpose: canonical creator identity independent of source/provider spelling.
  Invariants: displayName is mutable; normalizedName is matching evidence only,
  not identity.

SourceCreator (Planned Canonical)
  Purpose: source-platform creator provenance edge.
  Invariants: (sourcePlatformId, remoteCreatorId) is unique; provider IDs are
  evidence, not canonical Creator identity.

ContentCreator (Planned Canonical)
  Purpose: Content ↔ Creator role edge.
  Invariants: role is value-bearing (author, artist, translator, publisher,
  editor, other); source evidence is optional and never replaces the canonical edge.

ReaderSettings (Deferred)
  Purpose: user/device reader preferences.
  Invariants: reader-mode references to plugin readers use (pluginKey, modeId),
  never bare modeId.

ContentColorPalette (Deferred)
  Purpose: derived display palette for covers/library theming.
  Invariants: derived cache only; missing palette must not block content display.
```

Concurrency / consistency rules:

- All fetched bytes go through PluginProxy (allowlist + rate limit + redirect re-validation — `05_PLUGIN_SYSTEM.md`); the download manager gets no raw network privilege.
- Download and online reading share the same materialized ContentUnit rows. Provider URLs are provenance evidence, not identity; `unitId` remains the reader-position authority.
- A remote ContentUnit with `storageObjectId = null` is eligible for online fetch via PluginProxy when active remote provenance exists; it is not a local storage failure.
- Each unit write is one transaction: create StorageObject → create StoragePlacement (`role = authority`, respecting the at-most-one-authority partial unique index) → set `ContentUnit.storageObjectId`. A crash between units leaves resumable, not corrupt, state.
- Worker must re-read task status between units (and between chunks) so pause/cancel takes effect without killing the worker; status transitions are compare-and-swap style updates (`UPDATE ... WHERE status = 'fetching'`) to avoid racing a concurrent cancel.
- `doneUnits`/`bytesDone` counters are progress telemetry, not authority; on resume they are recomputed from actual placements, never trusted blindly.
- Update-check job and download tasks may run concurrently: section creation must rely on the `(source_link_id, remote_section_id)` unique constraint for dedup instead of check-then-insert.

---

## One-Time Old Venera Import: category and UI contracts

> **Canonical feature contract** for the separate trusted `LegacyImport` operation, not the general Plugin ImportJob or DownloadManager. Only `local.db`, `history.db`, `local_favorite.db`, `appdata.json` and `implicitData.json` are valid old-Venera metadata inputs. The legacy Unified Store `venera.db` is out of scope. `17_LEGACY_DISTRIBUTED_IMPORT.md` gives detailed parser/fixture evidence; Entities, DDL and Use Cases are authoritative in 01/02/03.

- **Dry-run, before any domain write:** user selects approved input roles and separately grants local asset directories, sees table/schema validity, per-file/category counts, source version, resolved versus unresolved works, estimated storage and reviewed conflict choices. Old files are not modified and there is no network/plugin execution.
- **Identity and re-import:** batch fingerprint identifies one snapshot; dataset-scoped per-record mapping identifies the old record. Repeated import or a changed `appdata.json` must preserve existing Content/Section/Unit and Collection IDs. New or conflicting metadata is presented as a reviewed change, not blind replace.
- **Local comics (L1 after M1):** verified images and ordered sections become new canonical works via normal domain/use cases; a missing folder results in a truthful metadata-only/unresolved entry only if user explicitly permits it. Tags/download state and source-only favorites are evidence, not automatically asserted canonical truth.
- **Reading progress (L1 after M1):** old `ep/page/readEpisode/chapter_group` needs proven old-version semantics and one verifiable `ContentUnitId`. Only then may `UC-005b` write the active session; existing v2 progress is preserved unless the user explicitly chooses to replace it. Ambiguous/remote history is shown as staged review evidence, not a fake reader target.
- **Folders and comic favorites (L2 after M2):** map valid `local_favorite.db` per-folder tables to UserCollection and member order; only create membership if a real ContentId is mapped. Unmatched remote favorites remain `LegacyUnresolvedRecord`.
- **Image favorites:** `history.db.image_favorites` is a separate category from comic favorites. Until an explicit image-level favorite model exists, show `DEFERRED_IMAGE_FAVORITES`; never silently remap individual favorite images into whole-comic UserCollection membership.
- **Tags and settings (L2 after M2):** apply only reviewed source tag mappings and allowlisted keys from `appdata.json` and `implicitData.json`. Before M2 tags remain bounded staging evidence; credentials, legacy scripts and unknown configuration keys are never imported.
- **Remote references (optional L3 after M3):** source-only history/favorites can be reviewed when SourceInstance/AccountProfile identity contracts are available. Do not run source plugins, attempt login, perform website requests or automatically select a different Account during the one-time import.
- **Crash/cancel UX:** show `selected → snapshotted → previewed → approved → applying → verified/partial/failed/cancelled` and asset journal recovery status. A partial batch can contain fully committed works but never a half-active ContentUnitOrder; cancellation doesn't delete earlier committed canonical content.
- **Receipt and privacy:** show `imported / unchanged / deferred / review_required / failed` counts for **every selected category**, with later review and independent purge of staging evidence. No “completed” claim while a requested category is deferred, no irreversible bulk deletion of originals and no secret-bearing diagnostics.

**Repository additions** to the full `CoreRepositories` target interface (phase-gated, not required by M1 minimum): `legacyImportDatasets: LegacyImportDatasetRepositoryPort`, `legacyImportBatches: LegacyImportBatchRepositoryPort`, `legacyRecordMappings: LegacyRecordMappingRepositoryPort`, `legacyUnresolvedRecords: LegacyUnresolvedRepositoryPort`, `legacyAssetJournal: LegacyAssetJournalRepositoryPort`, `legacyImportReceipts: LegacyImportReceiptRepositoryPort`. `04_PACKAGES_AND_PIECES.md` owns the application/adapter port boundary; `02_DATABASE_SCHEMA.md` owns the table DDL. These repositories aren't plugin accessible.

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
  anonymousSessionId: String  -- anonymous daily token (rotates daily, privacy);
                              -- NOT a ReadingSession reference — same concept as
                              -- 02 reading_events.anonymous_session_id
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
  anonymous_session_id TEXT NOT NULL,  -- anonymous daily token; NOT a ReadingSession id
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

Source-link deletion rule:
- SourceLink deletion must cancel queued/active download tasks for that source in the deleting transaction.
- Terminal download tasks retain history with `source_link_id = NULL` and `plugin_key` attribution.

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
// rating:>=4 → userRating filter (ContentMetadata.userRating, 1..5)
// author:"fujimoto" → author search
// lang:ja → language filter
// added:>7d → added within 7 days
// (chainsaw OR "csm") AND tag:action → boolean operators
```

```sql
-- content_fts (full-text over text units) is defined CANONICALLY in
-- 02_DATABASE_SCHEMA.md (§ Misc tables). Do NOT redefine it here.

-- Title search index (all content) — target fragment, pending consolidation into 02
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
    d. Metadata filters (type, status, userRating, date)
  4. Merge + deduplicate results
  5. Rank: FTS rank * 0.5 + semantic similarity * 0.3 + recency * 0.2
  6. Apply library_status filter (exclude removed unless requested)
  7. Return paginated SearchResult[]

interface SearchFilter {
  contentTypes?:  ContentType[]
  tags?:          CanonicalTagKey[]
  rating?:        { gte?: number; lte?: number }  // userRating 1..5
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
  query_preview TEXT,            -- user-facing LOCAL display only; never logged/telemetered/exported (Tier 0, see 06)
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
    contents: ContentMetadata[]      -- titles, tags, contentRating/userRating, NO bytes
    sourceLinks: SourceLink[]
    contentFingerprints: ContentFingerprint[]
    collections: UserCollection[]
    collectionItems: UserCollectionItem[]
    readingSessions: ReadingSession[] -- ACTIVE position rows only; unitId authority
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
        Content matched by identity ladder:
          1. SourceLink (sourcePlatformId, remoteWorkId)
          2. ContentFingerprint externalIds/hash evidence
          3. normalizedTitle + contentType as candidate only, requiring merge/keep_both/skip decision
        Default for ambiguous merge-mode matches: keep_both
        Reading sessions merged per content using ACTIVE-row semantics; newer
        active row wins, historical non-active rows never override resume state

UC-BACKUP-003: Sync Reading Position (Hosted Mode)
Flow:   Hosted multi-client extension only (not core single-runtime authority)
        On each UpdateReaderPosition for the ACTIVE row:
          1. Check session.version vs server version
          2. If conflict → emit sync.conflict notification
          3. User resolves: "Use mine" | "Use server" | "Keep both"
             ("Keep both" preserves the losing position as non-active history;
             exactly one active row still remains)
```

### Session Version for Conflict Detection

> Status: **Planned (hosted mode only)** — not core authority. The core contract
> (`02_DATABASE_SCHEMA.md`) is last-write-wins, single runtime, no version signal.
> These columns may only land together with an explicit multi-device
> conflict-resolution contract; do not add them speculatively to standalone builds.
> Conflict checks apply to the ACTIVE session row for the content (the schema allows
> historical non-active lifecycle rows). `device_id` is advisory conflict context,
> not position authority; `unitId` remains the saved-position authority.

```sql
-- Hosted-mode extension to reading_sessions
ALTER TABLE reading_sessions ADD COLUMN version INTEGER NOT NULL DEFAULT 1;
ALTER TABLE reading_sessions ADD COLUMN device_id TEXT;  -- which device last wrote
-- On conflict: client sends { expectedVersion: N }, server rejects if N != current
-- "Keep both" must demote the losing position to non-active history, never create
-- two active rows for one content.
```

---

## Content Filtering / Parental Controls

```
Entity: ContentFilterProfile
  id:              "singleton"
  enabled:         Boolean
  maxContentRating: Enum (safe | moderate | adult_only | explicit | all)
                    -- ordered ceiling on the ContentRating scale; 'all' = no ceiling
  blockedTags:     CanonicalTagKey[]   -- hide content with these tags
  blockedSourcePlatforms: String[]     -- hide content from these platforms
  requirePinToDisable: Boolean
  pinHash:         String?             -- argon2 hash of PIN

ContentRating enum:
  safe          -- G/PG content
  moderate      -- PG-13 / teen
  adult_only    -- M/R18 content
  explicit      -- explicit adult content

Rating scale is ORDERED: safe < moderate < adult_only < explicit.
maxContentRating is a ceiling on that scale ('all' = no ceiling).
Filtering rule (FAIL CLOSED): when the filter is enabled, content with NO
content_rating is treated as most restricted (hidden). Unrated content must
never leak past an enabled filter.
```

```sql
CREATE TABLE content_filter_profile (
  id                      TEXT PRIMARY KEY DEFAULT 'singleton',
  enabled                 INTEGER NOT NULL DEFAULT 0,
  max_content_rating      TEXT NOT NULL DEFAULT 'all'
    CHECK (max_content_rating IN ('safe','moderate','adult_only','explicit','all')),
  blocked_tags_json       TEXT NOT NULL DEFAULT '[]',
  blocked_platforms_json  TEXT NOT NULL DEFAULT '[]',
  require_pin_to_disable  INTEGER NOT NULL DEFAULT 0,
  pin_hash                TEXT,
  updated_at              TEXT NOT NULL
);

-- Content rating stored on content_metadata
-- content_metadata.content_rating and content_metadata.user_rating are defined
-- canonically in 02_DATABASE_SCHEMA.md because content_metadata is a 02-owned table.
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

  // One-time old Venera import (trusted application-only, phase-gated)
  legacyImportDatasets:       LegacyImportDatasetRepositoryPort
  legacyImportBatches:        LegacyImportBatchRepositoryPort
  legacyRecordMappings:       LegacyRecordMappingRepositoryPort
  legacyUnresolvedRecords:    LegacyUnresolvedRepositoryPort
  legacyAssetJournal:         LegacyAssetJournalRepositoryPort
  legacyImportReceipts:       LegacyImportReceiptRepositoryPort
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
