# Venera Entities
> Language-agnostic. All IDs are UUID v4 unless stated otherwise.

---

## Content (replaces Comic)

```
Entity: Content
  id:            ContentId (UUID v4, immutable)
  contentType:   ContentType enum
  normalizedTitle: String (lowercase, search signal only, non-unique)
  originHint:    Enum (unknown | local | remote | mixed)
  libraryStatus: Enum (active | removed)
  removedAt:     Timestamp? (present iff libraryStatus = removed)
  createdAt:     Timestamp
  updatedAt:     Timestamp

ContentType enum:
  comic | webtoon | illustrated | novel | article | document | note
```

**Invariants:**
- `id` immutable
- `normalizedTitle` non-unique, never identity authority
- `originHint` recomputed in same transaction as SourceLink changes
- `kind = virtual` SourcePlatforms do NOT contribute to `originHint`
- `removedAt` present iff `libraryStatus = removed`

---

## ContentMetadata

```
Entity: ContentMetadata
  contentId:           ContentId (FK, immutable)
  title:               String (denormalized cache of primary ContentTitle)
  description:         String?
  coverStatus:         Enum (none | pending | local_only | synced)
  coverUnitId:         ContentUnitId?
  coverStorageObjectId: StorageObjectId?
  authorName:          String?
  metadataJson:        JsonObject?
  createdAt:           Timestamp
  updatedAt:           Timestamp
```

**Invariants:**
- `title` must equal primary `ContentTitle.title` — updated atomically in same transaction
- `coverStatus = none` → both cover refs absent
- `coverStatus = local_only` → at least one cover ref present
- `coverStatus = synced` → `coverStorageObjectId` present with readable placement
- If both cover refs present: `coverUnitId.storageObjectId == coverStorageObjectId`

---

## ContentTitle

```
Entity: ContentTitle
  id:               ContentTitleId (UUID v4)
  contentId:        ContentId
  title:            String
  normalizedTitle:  String (non-unique, matching signal)
  titleKind:        Enum (primary | source | alias)
  locale:           String? (BCP-47)
  sourcePlatformId: SourcePlatformId?
  sourceLinkId:     SourceLinkId?
  createdAt:        Timestamp
```

**Invariants:**
- Exactly one `titleKind = primary` per content (enforced by DB partial unique index)
- `normalizedTitle` is non-unique, non-identity

---

## ContentSection (replaces Chapter)

```
Entity: ContentSection
  id:               ContentSectionId (UUID v4, immutable)
  contentId:        ContentId (immutable)
  parentSectionId:  ContentSectionId? (self-ref for nesting)
  sectionKind:      ContentSectionKind enum
  sectionNumber:    DecimalString? (ordering hint only, non-unique, non-identity)
  title:            String?
  displayLabel:     String?
  createdAt:        Timestamp
  updatedAt:        Timestamp

ContentSectionKind enum:
  season | volume | chapter | episode | oneshot | group  ← visual content
  section | entry | article | part                       ← text content
```

**Invariants:**
- `sectionNumber` compared with decimal semantics, never float arithmetic
- `parentSectionId` must not equal own `id`
- Hierarchy must be acyclic; max depth 8 nodes
- Identity is `id` only; `sectionNumber` is ordering hint

---

## ContentUnit (replaces Page)

```
Entity: ContentUnit
  id:                  ContentUnitId (UUID v4, immutable)
  sectionId:           ContentSectionId (immutable)
  unitIndex:           Integer (0-based, unique within section, gaps allowed)
  unitType:            ContentUnitType enum

  # Image units (comic/webtoon)
  storageObjectId:     StorageObjectId?
  mimeType:            String?
  width:               Integer?
  height:              Integer?
  checksum:            String?

  # Text units (novel/note/document)
  textContent:         String?
  textHash:            String?

  sectionSourceLinkId: SectionSourceLinkId?
  createdAt:           Timestamp
  updatedAt:           Timestamp

ContentUnitType enum:
  image | text | pdf_page | markdown | html
```

---

## ReadingSession (replaces ReaderSession)

```
Entity: ReadingSession
  id:           ReadingSessionId (UUID v4, immutable)
  contentId:    ContentId (immutable, UNIQUE — one session per content)
  unitId:       ContentUnitId (position authority)
  sourceLinkId: SourceLinkId? (read-context evidence, not position)
  sessionState: Enum (active | suspended | completed | abandoned)
  createdAt:    Timestamp
  updatedAt:    Timestamp
```

**Invariants:**
- UNIQUE constraint on `contentId` in DB — one row per content, upserted
- `chapterId` and `unitIndex` are derived by joining `ContentUnit`; never stored here
- `sessionState = active` is the resume candidate
- `sourceLinkId` is historical context only; stale links must not block fallback

---

## ContentRelationship (replaces ComicRelationship)

```
Entity: ContentRelationship
  id:                  ContentRelationshipId (UUID v4)
  sourceContentId:     ContentId
  targetContentId:     ContentId
  relationshipType:    Enum (translation | edition | sequel | prequel | spin_off | adaptation | alternative | colored)
  sourceLanguage:      String? (BCP-47, for translation)
  targetLanguage:      String? (BCP-47, for translation)
  sourceContentType:   ContentType
  targetContentType:   ContentType
  confidence:          Enum (manual | auto_high | auto_low)
  evidenceSignals:     String[] (title_similarity | cover_phash | external_id | chapter_structure | tag_overlap | embedding_cosine)
  createdAt:           Timestamp
  updatedAt:           Timestamp
```

---

## ContentFingerprint

```
Entity: ContentFingerprint
  id:              ContentFingerprintId (UUID v4)
  contentId:       ContentId (unique)
  coverPHash:      String?       (64-bit perceptual hash, hex)
  coverDHash:      String?
  sectionCount:    Integer
  unitCountHint:   Integer
  externalIds: {
    anilistId?:      Integer
    mangaUpdatesId?: String
    malId?:          Integer
    kitsuId?:        String
  }
  signalVersion:   String
  createdAt:       Timestamp
  updatedAt:       Timestamp
```

---

## ContentVector

```
Entity: ContentVector
  contentId:     ContentId (unique)
  titleVec:      Blob (float32[384], multilingual-e5-small)
  tagVec:        Blob (float32[N], one-hot canonical tags)
  contentRank:   Float (PageRank score on relationship graph)
  lastComputedAt: Timestamp
  signalVersion: String
```

---

## ContentRelationshipProposal

```
Entity: ContentRelationshipProposal
  id:              UUID v4
  sourceContentId: ContentId
  targetContentId: ContentId
  suggestedType:   RelationshipType
  confidence:      "auto_low"
  signalSummary:   JsonObject
  status:          Enum (pending | accepted | rejected | expired)
  reviewedAt:      Timestamp?
  expiresAt:       Timestamp
  createdAt:       Timestamp
```

---

## UserCollection

```
Entity: UserCollection
  id:                  UserCollectionId (UUID v4, immutable)
  displayName:         String (non-empty)
  description:         String?
  coverStorageObjectId: StorageObjectId?
  sortOrder:           Enum (manual | title | updated_at | last_read)
  createdAt:           Timestamp
  updatedAt:           Timestamp
```

## UserCollectionItem

```
Entity: UserCollectionItem
  id:           UserCollectionItemId (UUID v4, immutable)
  collectionId: UserCollectionId
  contentId:    ContentId
  sortIndex:    Integer (unique within collectionId)
  pinnedAt:     Timestamp?
  addedAt:      Timestamp
```

**Invariants:**
- `(collectionId, contentId)` unique
- `sortIndex` unique within `collectionId`
- Removed content may remain in collection until explicitly removed

---

## SourcePlatform

```
Entity: SourcePlatform
  id:            SourcePlatformId (UUID v4, immutable)
  canonicalKey:  String (unique, immutable, stable)
  displayName:   String
  kind:          Enum (local | remote | virtual, immutable)
  status:        Enum (active | disabled | deprecated)
  createdAt:     Timestamp
  updatedAt:     Timestamp
```

**kind semantics:**
- `local` — local/imported storage
- `remote` — network/provider integration, content-bearing
- `virtual` — internal synthesized only; must NOT fetch remote content, own credentials, or model user collections

**Status transitions:**
- `active ↔ disabled` (reversible)
- `active → deprecated`, `disabled → deprecated` (one-way, terminal)
- `deprecated → *` REJECTED

---

## SourceLink

```
Entity: SourceLink
  id:               SourceLinkId (UUID v4)
  contentId:        ContentId
  sourcePlatformId: SourcePlatformId
  remoteWorkId:     String (stable, source-side identifier)
  remoteUrl:        String? (sanitized)
  displayTitle:     String?
  linkStatus:       Enum (active | candidate | rejected | stale)
  confidence:       Enum (manual | auto_high | auto_low)
  createdAt:        Timestamp
  updatedAt:        Timestamp
```

**Invariants:**
- `(sourcePlatformId, remoteWorkId)` UNIQUE — enforced by DB index
- Identity remains owned by `Content`, not this provenance edge

---

## SectionSourceLink (replaces ChapterSourceLink)

```
Entity: SectionSourceLink
  id:               SectionSourceLinkId (UUID v4)
  sectionId:        ContentSectionId
  sourceLinkId:     SourceLinkId
  remoteSectionId:  String
  remoteUrl:        String?
  remoteLabel:      String?
  sourceOrder:      Integer? (used for MIN aggregation in canonical sort)
  linkStatus:       Enum (active | inactive | stale)
  confidence:       Enum (manual | auto_high | auto_low)
  createdAt:        Timestamp
  updatedAt:        Timestamp
```

**Invariants:**
- `(sourceLinkId, remoteSectionId)` UNIQUE
- `sourceOrder` is ordering hint; `MIN(sourceOrder)` across active links = canonical sort position

---

## ContentUnitOrder (replaces PageOrder)

```
Entity: ContentUnitOrder
  id:        ContentUnitOrderId (UUID v4)
  sectionId: ContentSectionId (immutable)
  orderType: Enum (source | user_override | import_detected | custom)
  status:    Enum (active | inactive | superseded | archived)
  createdAt: Timestamp
  updatedAt: Timestamp
```

**Invariants:**
- Exactly one `status = active` per section (DB partial unique index)
- No `pageCount` cache — derived from `ContentUnitOrderItem` rows

## ContentUnitOrderItem (replaces PageOrderItem)

```
Entity: ContentUnitOrderItem
  id:          ContentUnitOrderItemId (UUID v4)
  orderId:     ContentUnitOrderId
  unitId:      ContentUnitId
  sortIndex:   Integer (unique within orderId)
  createdAt:   Timestamp
```

---

## StorageBackend

```
Entity: StorageBackend
  id:                  StorageBackendId (UUID v4, immutable)
  backendKey:          String (unique, stable)
  displayName:         String
  backendKind:         Enum (local_app_data | webdav | plugin | future)
  configJson:          String (NO plaintext secrets)
  configSchemaVersion: Integer
  secretRef:           String? (OS keychain/keystore ref, NOT raw credential)
  status:              Enum (active | disabled | deprecated)
  createdAt:           Timestamp
  updatedAt:           Timestamp
```

## StorageObject

```
Entity: StorageObject
  id:          StorageObjectId (UUID v4, immutable)
  objectKind:  Enum (unit_image | cover | archive | backup | cache)
  contentHash: String? (evidence for dedup, not identity)
  sizeBytes:   Integer?
  mimeType:    String?
  createdAt:   Timestamp
  updatedAt:   Timestamp
```

**Invariants:**
- Row existence does NOT imply byte availability
- Availability determined by `StoragePlacement` with readable `syncStatus`
- Loader must surface `STORAGE_OBJECT_UNAVAILABLE`, not treat row as success

## StoragePlacement

```
Entity: StoragePlacement
  id:               StoragePlacementId (UUID v4)
  storageObjectId:  StorageObjectId
  storageBackendId: StorageBackendId
  objectKey:        String
  role:             Enum (authority | cache | mirror | staging)
  syncStatus:       Enum (pending | uploading | synced | failed | evicted)
  lastVerifiedAt:   Timestamp?
  createdAt:        Timestamp
  updatedAt:        Timestamp
```

**Invariants:**
- `(storageObjectId, storageBackendId, objectKey)` UNIQUE
- At most one `role = authority` per `storageObjectId` — enforced by DB partial unique index

---

## Auth Entities

```
Entity: AuthUser
  id:          AuthUserId (UUID v4)
  displayName: String
  role:        Enum (owner | admin | viewer)
  status:      Enum (active | suspended | removed)
  createdAt:   Timestamp
  updatedAt:   Timestamp

Invariants:
  - Exactly one owner must exist per instance
  - Cannot remove last owner

Entity: AuthSession
  id:          AuthSessionId (UUID v4)
  userId:      AuthUserId
  method:      Enum (passkey | oauth | api_key | local_password | magic_link)
  tokenHash:   String (argon2, write-once, immutable)
  expiresAt:   Timestamp
  lastUsedAt:  Timestamp?
  ipHash:      String? (one-way, anomaly detection only)
  userAgent:   String?
  createdAt:   Timestamp

Entity: Passkey
  id:           PasskeyId (UUID v4)
  userId:       AuthUserId
  credentialId: String (UNIQUE, WebAuthn base64url)
  publicKey:    String (COSE base64url)
  signCount:    Integer (replay guard; must increase on every use)
  deviceName:   String
  aaguid:       String?
  lastUsedAt:   Timestamp?
  createdAt:    Timestamp

Entity: ApiKey
  id:          ApiKeyId (UUID v4)
  userId:      AuthUserId
  keyHash:     String (shown ONCE, then hashed — NEVER retrievable)
  displayName: String
  scopes:      Permission[] (immutable after creation)
  expiresAt:   Timestamp?
  lastUsedAt:  Timestamp?
  revokedAt:   Timestamp?
  createdAt:   Timestamp

Entity: OAuthConnection
  id:                 OAuthConnectionId (UUID v4)
  userId:             AuthUserId
  provider:           Enum (google | github | discord | custom_oidc)
  providerUserId:     String
  providerEmailHash:  String? (one-way)
  accessTokenRef:     String (secretRef, NOT raw token)
  refreshTokenRef:    String (secretRef, NOT raw token)
  tokenExpiresAt:     Timestamp
  createdAt:          Timestamp
  updatedAt:          Timestamp

Invariants (all auth):
  - tokenHash / keyHash: write-once, never logged, never returned after creation
  - ipHash: one-way, cannot be reversed
  - All secrets via secretRef to OS credential store
  - signCount regression on Passkey → fail closed, emit auth.passkey.replay_detected
```

---

## Telemetry & Audit Entities

```
Entity: AuditEvent (append-only)
  id:             UUID v4
  seq:            Integer (monotonic per stream; gap = tamper signal)
  streamId:       String
  eventId:        UUID v4 (UNIQUE; dedup replays)
  schemaVersion:  String
  actorKind:      Enum (user | system | plugin | api_key)
  actorId:        String (server-resolved, NEVER client-supplied)
  actorRole:      String?
  actorIpHash:    String?
  recordedAt:     String (server UTC, NOT client time)
  idempotencyKey: String?
  payloadJson:    String (TIER 2 safe fields only — see privacy tiers)
  payloadHash:    String (SHA-256 of canonical JSON payload)
  prevHash:       String? (NULL for stream-first event)
  eventCore:      String (canonical JSON of metadata + prevHash + payloadHash)
  eventHash:      String (SHA-256 of eventCore; UNIQUE)
  signature:      String (HMAC-SHA256 of eventHash)
  signingKeyId:   String

Invariants:
  - Repository port must NOT expose update or delete methods
  - seq must be monotonically increasing per streamId
  - prevHash must equal previous event's eventHash in same stream

Entity: AuditCheckpoint
  id:              UUID v4
  checkpointSeq:   Integer (UNIQUE)
  streamsJson:     String (List<{streamId, latestSeq, latestHash}>)
  merkleRoot:      String
  eventCount:      Integer
  signature:       String
  signingKeyId:    String
  createdAt:       Timestamp

Entity: TelemetryConsent
  id:           UUID v4
  consentType:  Enum (crash_report | community_telemetry | plugin_reporting | feedback)
  given:        Boolean
  policyVersion: String (immutable once set)
  givenAt:      Timestamp?
  revokedAt:    Timestamp?
  createdAt:    Timestamp
  updatedAt:    Timestamp

Invariants:
  - At most one active consent per consentType
  - New policy version requires new record (cannot mutate existing)
```

---

## Plugin Package Entities

```
Entity: SourceRepository
  id:                  SourceRepositoryId (UUID v4)
  displayName:         String
  primaryUrl:          String
  mirrorUrls:          String[] (JSON)
  publicKeyFingerprint: String (Ed25519)
  publicKeyMaterial:   String (Ed25519 public key)
  trustTier:           Enum (official | community | self_hosted)
  discoveryMethod:     Enum (builtin | mdns | url_scheme | dns_txt | manual)
  status:              Enum (active | disabled)
  lastIndexSyncedAt:   Timestamp?
  createdAt:           Timestamp
  updatedAt:           Timestamp

Entity: SourcePackageManifest
  id:              String (deterministic SHA-256 hash of canonical manifest, NOT UUID v4)
  sourcePlatformId: SourcePlatformId? (optional, post-activation only)
  packageKey:      String
  providerKey:     String
  version:         String (semver)
  archiveSha256:   String (lowercase hex)
  runtimeRequires: String (semver range)
  apiLevel:        Integer
  pluginLayer:     Enum (declarative | sdk | full)
  contentTypes:    ContentType[] (which content types this plugin supports)
  permissions:     Permission[] (declared, validated at install)
  trustTier:       Enum (official | community | custom | unverified)
  publisherKeyFingerprint: String?
  reportEndpoint:  String? (plugin author's error reporting URL)
  i18nJson:        String? (plugin's own translations)
  manifestContract: JsonObject
  createdAt:       Timestamp

Entity: SourcePackageArtifact
  id:              String (UUID v4 or deterministic artifact ID)
  sourcePlatformId: SourcePlatformId?
  packageKey:      String
  providerKey:     String
  version:         String (semver)
  archiveSha256:   String (lowercase hex)
  packageStoreRef: String
  state:           Enum (committed | active | orphaned | cleanup_pending | removed)
  verificationTier: Enum (official | community | custom | unverified)
  createdAt:       Timestamp
  updatedAt:       Timestamp
```

---

## Recommendation Entities

```
Entity: ReadingEvent
  id:             UUID v4
  contentId:      ContentId
  sectionId:      ContentSectionId
  sessionId:      String (anonymous, rotates daily)
  completionRate: Float (0.0 - 1.0)
  durationMs:     Integer?
  recordedAt:     Timestamp

Entity: RecommendationFeedback
  id:              UUID v4
  sourceContentId: ContentId
  targetContentId: ContentId
  action:          Enum (click | dismiss | save)
  algorithm:       String
  rank:            Integer
  recordedAt:      Timestamp

Entity: TrainingSignal
  id:          UUID v4
  signalType:  String
  payloadJson: String
  processed:   Boolean (default false)
  recordedAt:  Timestamp
```

---

## Setup Entity

```
Entity: SetupState
  id:              "singleton" (only one row)
  completedSteps:  String[] (JSON)
  isComplete:      Boolean
  completedAt:     Timestamp?
  instanceName:    String?
  deploymentMode:  Enum (standalone | hosted)
  createdAt:       Timestamp
  updatedAt:       Timestamp
```

---

## Note-Specific Entity

```
Entity: NoteLink
  id:              UUID v4
  sourceContentId: ContentId
  targetContentId: ContentId
  linkText:        String ([[link text]])
  resolved:        Boolean
  createdAt:       Timestamp

Entity: ContentAnnotation
  id:             UUID v4
  contentId:      ContentId
  unitId:         ContentUnitId
  annotationType: Enum (highlight | comment | bookmark)
  startOffset:    Integer
  endOffset:      Integer
  color:          String?
  comment:        String?
  createdAt:      Timestamp
  updatedAt:      Timestamp
```

---

## Client Network Entity (Standalone)

```
Entity: ClientNetworkConfig
  id:               "singleton"
  globalProxy:      String? (proxy name)
  proxiesJson:      String (ProxyConfig[])
  dnsJson:          String (DnsConfig)
  rulesJson:        String (NetworkRule[])
  sourceRulesJson:  String (Record<canonicalKey, overrides>)
  configSchemaVersion: Integer
  updatedAt:        Timestamp
```

---

## Operation Idempotency

```
Entity: OperationIdempotencyRecord
  operationName:      String
  idempotencyKey:     String
  inputHash:          String
  status:             Enum (in_progress | completed | failed)
  resultType:         String?
  resultResourceId:   String?
  resultJson:         String?
  resultSchemaVersion: String?
  createdAt:          Timestamp
  updatedAt:          Timestamp

Primary key: (operationName, idempotencyKey)

Invariants:
  - Same (operationName, idempotencyKey) + same inputHash + completed → replay
  - Same (operationName, idempotencyKey) + different inputHash → IDEMPOTENCY_CONFLICT
  - in_progress / failed records need TTL cleanup (TODO: implement cleanup job)
```
