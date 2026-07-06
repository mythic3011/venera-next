# Venera Plugin System
> Complete design for all plugin types: Provider, Importer, Exporter, Storage, Reader, Extension, Theme.
> Importers are plugins. Built-in handlers are official plugins. Everything is extensible.

---

## Plugin Types

```typescript
enum PluginType {
  PROVIDER  = "provider",    // content source (fetch from remote platform)
  IMPORTER  = "importer",    // import local files into library
  EXPORTER  = "exporter",    // export content out of library
  STORAGE   = "storage",     // custom storage backend
  READER    = "reader",      // custom reader UI (sheet music, vertical novel, etc.)
  EXTENSION = "extension",   // capability addon (OCR, translation, TTS, etc.)
  THEME     = "theme",       // UI theme only (no code execution)
}

// A plugin may declare multiple types
// e.g. EHentai plugin: ["provider", "importer"]
// e.g. Translate+OCR plugin: ["extension"] with both ocr and translation capabilities
```

---

## Plugin Manifest (Complete)

```typescript
interface PluginManifest {
  // ── Identity ───────────────────────────────────────────────────────
  id:          string    // reverse domain: "app.venera.copymanga"
  key:         string    // short stable key: "copymanga" (used in DB, logs, URLs)
  providerKey: string    // identity metadata only (see 01 SourcePackageManifest);
                         // never inferred from display/provider name text
  name:        string    // display name
  version:     string    // semver
  description: string
  author:      string
  website?:    string
  iconUrl?:    string

  // ── Compatibility ──────────────────────────────────────────────────
  runtimeRequires: string    // semver range e.g. ">=0.5.0"
  apiLevel:        number    // breaking changes increment this
  pluginLayer:     "declarative" | "sdk" | "full"   // sandbox/validation policy tier (06)

  // ── Types ─────────────────────────────────────────────────────────
  pluginTypes: PluginType[]

  // ── Entry Points (per type) ────────────────────────────────────────
  entry: {
    provider?:  string    // "dist/provider.js"
    importer?:  string    // "dist/importer.js"
    exporter?:  string    // "dist/exporter.js"
    storage?:   string    // "dist/storage.js"
    extension?: string    // "dist/extension.js"
    reader?:    string    // URL to reader component (iframe)
  }

  // ── Provider Config (if pluginTypes includes "provider") ───────────
  providerConfig?: {
    contentTypes:   ContentType[]
    allowedDomains: string[]          // EXACT domains, wildcard only for subdomains
    allowedPorts?:  number[]          // default [80, 443]
    supportsSearch:     boolean
    supportsCategories: boolean
    supportsRanking:    boolean
    supportsAuth:       boolean
  }

  // ── Importer Config (if pluginTypes includes "importer") ───────────
  importerConfig?: {
    handles: Array<{
      mimeTypes?:  string[]     // ["application/zip"]
      extensions?: string[]     // [".cbz", ".cb7"]
      magicBytes?: number[][]   // [[0x50, 0x4B]] for ZIP
      description: string       // "CBZ/CB7 Comic Archives"
    }>
    outputContentTypes:     ContentType[]
    requiresFileAccess:     boolean
    supportsDirectoryInput: boolean
    requiresNetworkAccess?: boolean   // e.g. fetch covers during import
    maxConcurrent?:         number    // default 1
  }

  // ── Exporter Config (if pluginTypes includes "exporter") ───────────
  exporterConfig?: {
    outputFormats: Array<{
      mimeType:    string
      extension:   string
      description: string
    }>
    inputContentTypes: ContentType[]
    requiresNetworkAccess?: boolean
  }

  // ── Storage Config (if pluginTypes includes "storage") ─────────────
  storageConfig?: {
    storageTypeKey: string     // plugin-local storage type metadata; StorageBackend.backendKind is always "plugin"
    displayName:    string
    configSchema:   object     // JSON Schema for config form
    supportsStreaming: boolean
    requiresAuth:     boolean
  }

  // ── Reader Config (if pluginTypes includes "reader") ───────────────
  readerConfig?: {
    modeId:       string
    displayNames: Record<string, string>    // locale → label
    contentTypes: ContentType[]
    componentUrl: string                    // sandboxed iframe URL
    settingsSchema: object                  // JSON Schema
    settingsDefaults: object
  }

  // ── Extension Config (if pluginTypes includes "extension") ─────────
  extensionConfig?: {
    capabilities: ExtensionCapability[]
    // Declare which capabilities are implemented
  }

  // ── Permissions (subset of Permissions enum) ──────────────────────
  permissions: string[]      // validated against Roles.PLUGIN allowed set at install

  // ── Trust & Signing ────────────────────────────────────────────────
  // Manifest-level tier is publisher INTENT: official | community | custom.
  // "unverified" exists ONLY as an install-time verification RESULT
  // (verificationTier on the artifact), never as a manifest declaration.
  trustTier:               "official" | "community" | "custom"
  publisherKeyFingerprint?: string    // Ed25519 fingerprint; REQUIRED for official/community,
                                      // optional for custom (then artifact verifies as unverified
                                      // and needs advanced-user confirmation)
  // NOTE: archiveSha256 is deliberately NOT a manifest field. Archive hashes
  // live only in the SIGNED repository index/package entry (08) — a hash
  // inside the archive cannot protect the archive that contains it.

  // ── Network (importer/exporter only) ──────────────────────────────
  allowedDomains?: string[]    // additional domains beyond providerConfig

  // ── Storage quota (plugin-scoped key-value storage) ───────────────
  storageQuotaKB?: number      // default 1024 (1MB)

  // ── Reporting ─────────────────────────────────────────────────────
  reportEndpoint?:     string
  reportPrivacyUrl?:   string

  // ── i18n (plugin UI strings) ──────────────────────────────────────
  i18n?: {
    defaultLocale: string
    messages: Record<string, Record<string, string>>
  }
}
```

---

## Plugin Trust Tiers

```
Tier 0 — Official
  Signed by Venera maintainer key (Ed25519)
  Pre-audited + automated CI/CD
  Bundled with app or from official repository
  Isolation: shared (faster, trusted)
  UI: [Install] ✓ Verified

Tier 1 — Community
  Signed by publisher key (vpm-signer)
  Basic automated checks (no dangerous API usage)
  From community repository
  Isolation: full (separate worker)
  UI: [Install] ⚠ Community

Tier 2 — Custom
  Unsigned or self-signed
  User accepts responsibility
  Isolation: full + stricter limits
  UI: [Install (Advanced)] — requires confirmation dialog

Trust chain:
  Official repo index (signed) → Package entry (signed) → Archive bytes
  Mirror serves bytes only — trust is cryptographic, not server-based
```

---

## Plugin Security Boundary

- Manifest `trustTier` is publisher intent only. Executability depends on install-time `verificationTier` recorded on the committed artifact; `unverified` is never a manifest value and never executable.
- Shared isolation is reserved for bundled official plugins shipped with the runtime. Repository-delivered packages stay in `full` isolation unless the runtime explicitly classifies them as built-in code.
- Plugins never get direct DB, arbitrary filesystem, or raw network capability. DB work goes through runtime ports; importer reads are sandboxed to the granted source path; outbound fetch always goes through PluginProxy.
- Install authority is ordered: authenticity/integrity verification → PackageStore commit → `source_platform` mutation. `08_SOURCE_PACKAGE_LIFECYCLE.md` is the authoritative long-form contract.

---

## Plugin Runtime Architecture

```
Main Process
  │
  ├── PluginRuntimePiece
  │     ├── PluginRegistry      (active plugin map)
  │     ├── PluginLoader        (install, verify, activate)
  │     ├── ImportHandlerRegistry (importer plugins)
  │     ├── ExporterRegistry
  │     ├── ExtensionRegistry
  │     ├── PluginProxy         (intercept all outbound calls)
  │     └── PluginConsole       (log aggregation → WebSocket)
  │
  └── WorkerPool
        ├── Worker[copymanga]        (full isolation)
        ├── Worker[importer-archive] (official: shared isolation)
        └── Worker[storage-s3]       (full isolation)

Isolation levels:
  shared  → same process, VM context isolation (official plugins only)
  full    → separate Worker/isolate (community + custom plugins)
  native  → main process, no sandbox (reserved for core modules only)
```

---

## Plugin ↔ Runtime Message Protocol

```typescript
// Runtime → Plugin
type R2P =
  | { type: "init";              id: string; config: PluginInitConfig }
  | { type: "provider.search";   id: string; query: SearchQuery }
  | { type: "provider.detail";   id: string; contentId: string }
  | { type: "provider.sections"; id: string; contentId: string }
  | { type: "provider.units";    id: string; sectionId: string }
  | { type: "provider.categories"; id: string }
  | { type: "provider.login";    id: string; credentials: unknown }
  | { type: "importer.can_handle"; id: string; file: ImportFileInfo }
  | { type: "importer.import";   id: string; file: ImportFileInfo; ctx: ImportCtxConfig }
  | { type: "exporter.export";   id: string; contentIds: string[]; format: string }
  | { type: "storage.get";       id: string; key: string }
  | { type: "storage.put";       id: string; key: string; dataB64: string }
  | { type: "storage.delete";    id: string; key: string }
  | { type: "storage.list";      id: string; prefix?: string }
  | { type: "extension.ocr";     id: string; imageB64: string; options: OcrOptions }
  | { type: "extension.translate"; id: string; text: string; from: string; to: string }
  | { type: "shutdown" }

// Plugin → Runtime
type P2R =
  | { type: "ready" }
  | { type: "error";             code: string; message: string; fatal: boolean }
  | { type: "response";          id: string; result: unknown; error?: PluginError }
  | { type: "api.fetch";         id: string; url: string; init?: RequestInit }
  | { type: "api.log";           level: string; message: string; data?: object }
  | { type: "api.storage.get";   id: string; key: string }
  | { type: "api.storage.set";   id: string; key: string; value: string }
  | { type: "api.cache.get";     id: string; cacheKey: string }
  | { type: "api.cache.set";     id: string; cacheKey: string; dataB64: string; ttlSec?: number }
  | { type: "importer.progress"; data: ImportProgress }
  | { type: "importer.decision"; id: string; request: ImportDecision<unknown> }
  | { type: "importer.done";     id: string }
  | { type: "exporter.progress"; data: ExportProgress }
  | { type: "exporter.done";     id: string; outputPath: string }
```

---

## Plugin Proxy (Security Enforcement)

All plugin outbound calls pass through PluginProxy:

```typescript
class PluginProxy {

  async handleFetch(pluginKey: string, manifest: PluginManifest, url: string, init?: RequestInit) {
    // 0. Scheme allowlist: http/https ONLY (no file:, data:, ftp:, blob:)
    const parsed = new URL(url)
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
      throw new PluginError({ code: "NETWORK_BLOCKED", message: `scheme ${parsed.protocol} not allowed` })
    }

    // 1. Domain allowlist (HARD block) + port allowlist
    const domain = parsed.hostname
    if (!this.checkDomainAllowed(domain, manifest)) {
      throw new PluginError({ code: "NETWORK_BLOCKED", message: `${domain} not in allowedDomains` })
    }
    // SSRF guard: reject IP literals and any DNS resolution to loopback/private/
    // link-local ranges (127/8, 10/8, 172.16/12, 192.168/16, 169.254/16, ::1, fc00::/7).
    // Pin the resolved IP for the actual connection (resolve-once) to prevent
    // DNS-rebinding between check and use.
    await this.assertPublicAddress(domain)

    // 2. Rate limit: burst (5/sec) + sustained (60/min per domain)
    await this.rateLimiter.check(`plugin:${pluginKey}:${domain}`)

    // 3. Timeout
    const signal = AbortSignal.timeout(TimeoutPolicy.pluginFetch)

    // 4. Strip dangerous request headers (Cookie, Authorization unless declared,
    //    Host override, X-Forwarded-*)
    const safeInit = sanitizeRequestInit(init)

    // 5. Execute with MANUAL redirect handling: every redirect target must
    //    re-pass steps 0-1 (scheme + allowlist + public-address). Auto-follow
    //    would let an allowlisted server 302 the plugin to internal services.
    const response = await this.fetchWithValidatedRedirects(url, { ...safeInit, signal, redirect: "manual" })

    // 6. Response size cap (default 32 MB) — stream-abort past the limit.

    // 7. Audit
    await this.audit.append({ streamId: `plugin.${pluginKey}`, eventName: "plugin.fetch", payload: { urlPattern: toUrlPattern(url), status: response.status } })
    return response
  }

  async handleFileRead(pluginKey: string, requestedPath: string, allowedRoot: string): Promise<Buffer> {
    // Importer file access: sandboxed to provided source path only.
    // realpath (NOT resolve): path.resolve does not follow symlinks, so a
    // symlink inside allowedRoot pointing at /etc/passwd would pass a
    // startsWith check on the unresolved path.
    const realRoot = await fs.promises.realpath(allowedRoot)
    const real     = await fs.promises.realpath(requestedPath)
    // path.sep guard: prevents "/data/import-evil" passing for root "/data/import"
    if (real !== realRoot && !real.startsWith(realRoot + path.sep)) {
      throw new PluginError({ code: "FILE_ACCESS_DENIED", message: `Path outside sandbox` })
    }
    return fs.promises.readFile(real)
    // TOCTOU note: realpath-then-read is best-effort on general filesystems;
    // the real isolation boundary is the worker sandbox + read-only bind of the
    // import source directory where the platform supports it.
  }
}
```

---

## SDK: defineProvider

```typescript
// @venera/sdk/src/provider.ts

export function defineProvider(def: ProviderDefinition): void {
  self.onmessage = async ({ data }: MessageEvent<R2P>) => {
    if (data.type === "init") { self.postMessage({ type: "ready" }); return }

    const handlers: Record<string, () => Promise<unknown>> = {
      "provider.search":    () => def.search(data.query),
      "provider.detail":    () => def.getDetail(data.contentId),
      "provider.sections":  () => def.getSections(data.contentId),
      "provider.units":     () => def.getUnits(data.sectionId),
      "provider.categories":() => def.getCategories?.() ?? Promise.resolve([]),
      "provider.login":     () => def.login?.(data.credentials) ?? Promise.reject("not supported"),
    }

    const handler = handlers[data.type]
    if (!handler) return

    try {
      const result = await handler()
      self.postMessage({ type: "response", id: data.id, result })
    } catch (err) {
      self.postMessage({ type: "response", id: data.id, error: normalizeError(err) })
    }
  }
}

interface ProviderDefinition {
  // Required
  search(query: SearchQuery): Promise<ContentListResult>
  getDetail(sourceContentId: string): Promise<ContentDetailResult>
  getSections(sourceContentId: string): Promise<SectionListResult>
  getUnits(remoteSectionId: string): Promise<UnitListResult>

  // Optional: discovery
  getCategories?(): Promise<CategoryResult[]>
  getLatestUpdates?(page: number): Promise<ContentListResult>
  getRanking?(type: string, page: number): Promise<ContentListResult>
  getByTag?(tag: string, page: number): Promise<ContentListResult>
  getByCreator?(creatorId: string, page: number): Promise<ContentListResult>
  getRecommended?(sourceContentId: string): Promise<ContentListResult>

  // Optional: auth
  authRequired?:    boolean
  getAuthFields?(): AuthField[]
  login?(credentials: Record<string, string>): Promise<AuthResult>
  logout?(): Promise<void>
  checkAuthStatus?(): Promise<AuthStatus>

  // Optional: account features
  markSectionRead?(remoteSectionId: string): Promise<void>
  addFavorite?(sourceContentId: string): Promise<void>
  getFavorites?(page: number): Promise<ContentListResult>

  // Optional: URL resolution override
  resolveUnitUrl?(rawUrl: string): Promise<string>
  getRequestHeaders?(): Record<string, string>
}
```

---

## SDK: defineImporter

```typescript
// @venera/sdk/src/importer.ts

export function defineImporter(def: ImporterDefinition): void {
  self.onmessage = async ({ data }: MessageEvent<R2P>) => {
    if (data.type === "init") { self.postMessage({ type: "ready" }); return }

    if (data.type === "importer.can_handle") {
      self.postMessage({ type: "response", id: data.id, result: def.canHandle(data.file) })
      return
    }

    if (data.type === "importer.import") {
      const ctx = buildImporterContext(data.ctx)
      const gen = def.import(data.file, ctx)
      for await (const progress of gen) {
        // decision requests block until user responds
        if (progress.type === "decision") {
          self.postMessage({ type: "importer.decision", id: progress.id, request: progress.request })
          // runtime will send back a "response" message with the decision
          const answer = await waitForDecisionResponse(progress.id)
          ctx._resolveDecision(progress.id, answer)
        } else {
          self.postMessage({ type: "importer.progress", data: progress })
        }
      }
      self.postMessage({ type: "importer.done", id: data.id })
    }
  }
}

interface ImporterDefinition {
  canHandle(file: ImportFileInfo): boolean
  detectContentType?(file: ImportFileInfo): Promise<ContentType>
  import(file: ImportFileInfo, ctx: ImporterContext): AsyncGenerator<ImportProgress>
}

interface ImportFileInfo {
  name:     string
  path:     string
  mimeType: string    // detected via magic number by runtime
  sizeBytes: number
}

type ImportProgress =
  | { type: "phase";    name: string; data?: object }
  | { type: "progress"; message: string; percent: number }
  | { type: "unit";     unitPath: string; done: number; total: number }
  | { type: "decision"; id: string; request: ImportDecision<unknown> }
  | { type: "warning";  message: string }
  | { type: "result";   contentId: string; status: "created" | "repaired" | "skipped" }

type ImportDecision<T> =
  | { type: "bundle_mode";   filename: string; childCount: number }   // → "one_comic_chapters" | "separate_comics" | "cancel"
  | { type: "content_type";  filename: string; detected: ContentType; options: ContentType[] }
  | { type: "duplicate";     title: string }                          // → "skip" | "replace" | "keep_both"
  | { type: "section_map";   sections: string[] }                     // → Record<string, string> (dir → section title)

interface ImporterContext {
  storage: {
    preflight(input: PreflightInput): Promise<PreflightDecision>
    registerContent(input: RegisterContentInput): Promise<RegisteredContent>
    allocateStorageObject(input: AllocateStorageInput): Promise<StorageObject>
    copyFile(srcPath: string, storageObjectId: string): Promise<void>
    readFile(path: string): Promise<Uint8Array>    // sandboxed: source paths only
  }
  trace: {
    phase(name: string, data?: object): void
    progress(message: string, percent: number): void
  }
  decide<T>(request: ImportDecision<T>): Promise<T>
  utils: ImporterUtils
  _resolveDecision(id: string, answer: unknown): void
}

interface ImporterUtils {
  // File system helpers (all sandboxed)
  detectFileType(path: string): Promise<string>
  naturalSort(names: string[]): string[]
  isHiddenOrMacMetadata(path: string): boolean
  flattenSingleWrapper(dirPath: string): Promise<string>
  isBundleArchive(dirPath: string): Promise<boolean>
  extractArchive(filePath: string, outDir: string, concurrency?: number): Promise<void>
  collectImages(dirPath: string): Promise<ImageFileInfo[]>

  // Metadata parsers
  readMetadataJson(dirPath: string): Promise<ImportMetadata | null>
  readComicInfoXml(dirPath: string): Promise<ComicInfo | null>
  parseEpub(filePath: string): Promise<EpubDocument>

  // Sandboxed read-only SQLite over import-source files (same realpath
  // sandbox rules as handleFileRead; read-only, no ATTACH, no writes)
  querySqlite(path: string, sql: string): Promise<Array<Record<string, unknown>>>

  // Sort
  naturalCompare(a: string, b: string): number
}

interface PreflightDecision {
  action: "create_new" | "repair_existing" | "conflict_existing_storage" | "conflict_existing_record"
  existingContentId?: string
  targetStorageKey:   string
}
```

---

## SDK: defineExporter

```typescript
// @venera/sdk/src/exporter.ts

export function defineExporter(def: ExporterDefinition): void {
  self.onmessage = async ({ data }: MessageEvent<R2P>) => {
    if (data.type === "init") { self.postMessage({ type: "ready" }); return }

    if (data.type === "exporter.export") {
      const ctx = buildExporterContext(data.ctx)
      const gen = def.export(data.contentIds, data.format, ctx)
      for await (const progress of gen) {
        self.postMessage({ type: "exporter.progress", data: progress })
      }
      self.postMessage({ type: "exporter.done", id: data.id, outputPath: ctx._outputPath })
    }
  }
}

interface ExporterDefinition {
  supportedFormats: ExportFormat[]
  export(contentIds: string[], format: string, ctx: ExporterContext): AsyncGenerator<ExportProgress>
}

interface ExportFormat {
  id:          string
  mimeType:    string
  extension:   string
  displayName: string
}

interface ExporterContext {
  // Read content from library
  content: {
    getContent(contentId: string): Promise<ContentDetail>
    getSections(contentId: string): Promise<SectionDetail[]>
    getUnits(sectionId: string): Promise<UnitDetail[]>
    readUnitBytes(storageObjectId: string): Promise<Uint8Array>
  }
  // Write output file
  output: {
    write(fileName: string, data: Uint8Array): Promise<void>
    writeStream(fileName: string): WritableStream
  }
  trace: { phase(name: string, data?: object): void }
}

type ExportProgress =
  | { type: "phase";    name: string }
  | { type: "progress"; message: string; percent: number }
  | { type: "content";  contentId: string; done: number; total: number }
```

---

## SDK: defineStorage

```typescript
// @venera/sdk/src/storage.ts

export function defineStorage(def: StorageDefinition): void {
  self.onmessage = async ({ data }: MessageEvent<R2P>) => {
    if (data.type === "init") {
      await def.init?.(data.config)
      self.postMessage({ type: "ready" })
      return
    }
    const handlers = {
      "storage.get":    () => def.get(data.key),
      "storage.put":    () => def.put(data.key, Buffer.from(data.dataB64, "base64")),
      "storage.delete": () => def.delete(data.key),
      "storage.list":   () => def.list(data.prefix),
    }
    try {
      const result = await handlers[data.type]?.()
      self.postMessage({ type: "response", id: data.id, result })
    } catch (err) {
      self.postMessage({ type: "response", id: data.id, error: normalizeError(err) })
    }
  }
}

interface StorageDefinition {
  init?(config: unknown): Promise<void>
  test(): Promise<boolean>
  get(key: string): Promise<Buffer | null>
  put(key: string, data: Buffer): Promise<void>
  delete(key: string): Promise<void>
  list(prefix?: string): Promise<string[]>
  exists?(key: string): Promise<boolean>
  getMetadata?(key: string): Promise<StorageObjectMeta>
  createSignedUrl?(key: string, expiresInSec: number): Promise<string>
}
```

---

## SDK: defineExtension

```typescript
// @venera/sdk/src/extension.ts

export function defineExtension(def: ExtensionDefinition): void {
  self.onmessage = async ({ data }: MessageEvent<R2P>) => {
    if (data.type === "init") { self.postMessage({ type: "ready" }); return }

    if (data.type === "extension.ocr" && def.ocr) {
      try {
        const result = await def.ocr.recognize(
          Buffer.from(data.imageB64, "base64"), data.options
        )
        self.postMessage({ type: "response", id: data.id, result })
      } catch (err) {
        self.postMessage({ type: "response", id: data.id, error: normalizeError(err) })
      }
    }

    if (data.type === "extension.translate" && def.translation) {
      try {
        const result = await def.translation.translate(data.text, data.from, data.to)
        self.postMessage({ type: "response", id: data.id, result })
      } catch (err) {
        self.postMessage({ type: "response", id: data.id, error: normalizeError(err) })
      }
    }
  }
}

enum ExtensionCapability {
  OCR         = "ocr",
  TRANSLATION = "translation",
  TTS         = "tts",
  IMAGE_FILTER = "image_filter",
  METADATA_ENRICHMENT = "metadata_enrichment",
}

interface ExtensionDefinition {
  capabilities: ExtensionCapability[]

  ocr?: {
    supportedMimeTypes: string[]
    recognize(imageData: Buffer, options: OcrOptions): Promise<OcrResult>
  }

  translation?: {
    supportedLocales:  string[]
    supportedPairs?:   Array<[string, string]>    // null = all pairs supported
    translate(text: string, from: string, to: string): Promise<string>
    translateBatch?(texts: string[], from: string, to: string): Promise<string[]>
  }

  tts?: {
    supportedLocales: string[]
    getVoices(locale: string): Promise<TtsVoice[]>
    synthesize(text: string, locale: string, voiceId?: string): Promise<Buffer>
  }

  imageFilter?: {
    availableFilters: string[]
    apply(imageData: Buffer, filter: string, options?: object): Promise<Buffer>
  }

  metadataEnrichment?: {
    // Given minimal metadata, return enriched version
    // e.g. fetch from AniList, MyAnimeList, Goodreads
    enrich(input: PartialContentMetadata): Promise<EnrichedMetadata>
  }
}
```

---

## Built-in Plugin Catalogue

All official plugins bundled with the app. `isolation: "shared"`, `trustTier: "official"`.

### Providers (official)
```
@venera/provider-copymanga     comic     copymanga.site
@venera/provider-mangadex      comic     mangadex.org
@venera/provider-jmcomic       comic     18comic.vip
@venera/provider-local         comic     local filesystem (virtual)
```

### Importers (official)
```
@venera/importer-archive       comic, webtoon       CBZ, CB7, CBR, ZIP
@venera/importer-pdf           document, comic      PDF (image or text)
@venera/importer-epub          novel, document      EPUB 2/3
@venera/importer-text          note, article        Markdown, plain text, HTML
@venera/importer-directory     any                  directory of images or files
@venera/importer-ehviewer      comic                EhViewer/EhPanda SQLite DB
```

### Importers (community examples)
```
@community/importer-tachiyomi  comic     Tachiyomi/Mihon .tachibk backup
@community/importer-komga      comic     Komga library
@community/importer-calibre    novel     Calibre metadata.db
@community/importer-obsidian   note      Obsidian vault (.obsidian directory)
@community/importer-notion     note      Notion export ZIP
@community/importer-moonreader comic     Moon+ Reader backup
```

### Exporters (official)
```
@venera/exporter-cbz           comic → CBZ archive
@venera/exporter-pdf           any   → PDF
@venera/exporter-epub          novel → EPUB
@venera/exporter-markdown      note  → Markdown ZIP
```

### Storage (official)
```
@venera/storage-s3             S3-compatible (AWS/R2/MinIO/B2/Wasabi)
@venera/storage-webdav         WebDAV
@venera/storage-openlist       OpenList/AList integration
@venera/storage-ftp            FTP/FTPS
@venera/storage-sftp           SFTP
```

### Extensions (official)
```
@venera/extension-ocr          OCR for image-based content
@venera/extension-translate    Machine translation (multiple backends)
```

### Readers (official)
```
@venera/reader-sheet-music     Sheet music (MusicXML, ABC notation)
@venera/reader-vertical-novel  Vertical text novel reader
```

---

## Plugin Lifecycle

The state list below is a user-facing lifecycle view. Durable authority is split:

- Package acquisition/artifact state is owned by `source_package_artifacts.state`
  and `08_SOURCE_PACKAGE_LIFECYCLE.md`.
- Runtime plugin state is owned by `installed_plugins.state`.
- Absence of an `installed_plugins` row means "not installed"; `not_installed`
  is not a stored row value.
- Installer transients (`downloading`, `verifying`) are orchestration status
  surfaced over progress/events, not durable installed-plugin state.

```
States:
  not_installed     ← no installed_plugins row
  downloading       ← installer orchestration status
  verifying         ← installer orchestration status
  committed         ← source_package_artifacts.state
  installing        ← source_platform mutation in progress (installer orchestration)
  installed         ← SourcePlatform created, ready to activate
  activating        ← worker starting, init message sent
  active            ← worker ready, responding to messages
  disabled          ← installed but not loaded
  update_available  ← newer version in repository
  load_error        ← worker failed to start or crashed
  uninstalling      ← being removed
  orphaned          ← source_package_artifacts.state
  cleanup_pending   ← source_package_artifacts.state

Valid Transitions:
  not_installed → downloading (user installs)
  downloading → verifying (bytes received)
  verifying → committed (hash + sig valid)
  verifying → not_installed (hash/sig fail)
  committed → installing (start source_platform mutation)
  installing → installed (mutation success)
  installing → orphaned (mutation failed)
  orphaned → cleanup_pending (cleanup job picks up)
  cleanup_pending → not_installed (cleanup complete)
  installed → activating (activate())
  activating → active (worker "ready")
  activating → load_error (worker failed)
  active → disabled (disable())
  disabled → activating (re-enable)
  active → update_available (new version detected)
  update_available → downloading (user updates)
  load_error → activating (retry, max 3)
  load_error → uninstalling
  active/disabled/load_error → uninstalling (uninstall())
  uninstalling → not_installed

Rules:
  - At most ONE active worker per pluginKey
  - Worker crash → load_error + restart attempt (max 3, exponential backoff)
  - Orphaned artifacts → cleanup job runs async, max 24h TTL
  - "committed" with no state transition after 5min → stuck detection job → orphaned
  - Storage-plugin uninstall disables any StorageBackend rows where
    backend_kind = "plugin" and plugin_key matches the removed plugin; bytes are
    not deleted unless the storage-backend delete use case explicitly chooses it.
  - HARD COMMIT ORDER (authoritative contract in 08_SOURCE_PACKAGE_LIFECYCLE.md):
      authentic + verified artifact -> PackageStore commit -> source_platform mutation
    source_platform mutation NEVER before commit; commit NEVER before
    authenticity + integrity verification; failed mutation -> rollback or orphan.
  - Mutation idempotency: same packageKey+providerKey+version+archiveSha256 = no-op;
    same identity with DIFFERENT archiveSha256 = conflict, fail closed.
```

---

## Import Pipeline: Archive Handler Example

Demonstrates how a built-in importer uses defineImporter + ImporterUtils.

```typescript
// @venera/importer-archive/src/index.ts

export default defineImporter({
  canHandle(file) {
    return ["application/zip", "application/x-7z-compressed", "application/vnd.rar"]
      .includes(file.mimeType)
  },

  async *import(file, ctx) {
    yield { type: "phase", name: "archive.extract.start" }

    // Extract to temp dir (runtime handles, not plugin)
    const tmpDir = await ctx.utils.extractArchive(file.path, "__tmp__")

    try {
      // Flatten single wrapper (legacy ✅)
      const root = await ctx.utils.flattenSingleWrapper(tmpDir)

      // Bundle detection (legacy ✅)
      if (await ctx.utils.isBundleArchive(root)) {
        yield* handleBundle(root, file, ctx)
      } else {
        yield* handleFlat(root, file, ctx)
      }
    } finally {
      // always clean up
      yield { type: "phase", name: "cache.cleaned" }
    }
  },
})

async function* handleFlat(root, file, ctx): AsyncGenerator<ImportProgress> {
  const meta = await ctx.utils.readMetadataJson(root)
    ?? await ctx.utils.readComicInfoXml(root)
    ?? { title: file.name.replace(/\.[^.]+$/, ""), authors: [], tags: [] }

  yield { type: "phase", name: "metadata.resolved", data: { title: meta.title } }

  const preflight = await ctx.storage.preflight({
    normalizedTitle: normalizeTitle(meta.title),
    contentType:     "comic",
  })

  if (preflight.action === "conflict_existing_record") {
    const decision = await ctx.decide({ type: "duplicate", title: meta.title })
    if (decision === "skip") {
      yield { type: "result", contentId: preflight.existingContentId!, status: "skipped" }
      return
    }
  }

  const images = ctx.utils.naturalSort(
    (await ctx.utils.collectImages(root))
      .filter(f => !ctx.utils.isHiddenOrMacMetadata(f.path))
      .map(f => f.path)
  )

  yield { type: "phase", name: "images.collected", data: { count: images.length } }

  // Allocate storage objects and copy files
  const storageObjects = await Promise.all(images.map(imgPath =>
    ctx.storage.allocateStorageObject({
      objectKind: "unit_image",
      mimeType:   detectImageMime(imgPath),
    })
  ))

  let done = 0
  for (let i = 0; i < images.length; i++) {
    await ctx.storage.copyFile(images[i], storageObjects[i].id)
    yield { type: "unit", unitPath: images[i], done: ++done, total: images.length }
  }

  // Register with repair path support (legacy ✅)
  const registered = await ctx.storage.registerContent({
    existingContentId:     preflight.existingContentId,
    contentType:           "comic",
    title:                 meta.title,
    authorName:            meta.authors?.[0],
    tags:                  meta.tags?.map(t => ({ tag: t })),
    sections:              [{ sectionKind: "chapter", unitCount: images.length }],
    coverStorageObjectId:  storageObjects[0].id,
    sourcePlatformKey:     "local",
  })

  yield { type: "result", contentId: registered.content.id, status: preflight.existingContentId ? "repaired" : "created" }
}

async function* handleBundle(root, file, ctx): AsyncGenerator<ImportProgress> {
  const mode = await ctx.decide({
    type: "bundle_mode",
    filename: file.name,
    childCount: (await ctx.utils.collectImages(root)).length,
  })

  if (mode === "cancel") return

  if (mode === "one_comic_chapters") {
    // Import as single content with multiple sections
    yield* handleBundleAsSingleContent(root, file, ctx)
  } else {
    // Import each sub-archive as separate content
    yield* handleBundleAsSeparateContents(root, file, ctx)
  }
}
```

---

## EhViewer Import Handler

```typescript
// @venera/importer-ehviewer/src/index.ts

export default defineImporter({
  canHandle(file) {
    // file.mimeType is magic-number-detected by the runtime (invariant 31:
    // never trust extension alone). SQLite magic: "SQLite format 3\0".
    return file.mimeType === "application/vnd.sqlite3"
      && (file.name.endsWith(".db") || file.name.endsWith(".ehv"))
  },

  async *import(file, ctx) {
    yield { type: "phase", name: "ehviewer.db.open" }

    // Runtime provides sandboxed SQLite read utility
    const rows = await ctx.utils.querySqlite(file.path, `
      SELECT DN.DIRNAME, DL.TITLE, DL.TITLE_JPN, DL.CATEGORY, DL.TIME, LB.LABEL
      FROM DOWNLOAD_DIRNAME DN
      LEFT JOIN DOWNLOADS DL ON DL.GID = DN.GID
      LEFT JOIN DOWNLOAD_LABELS LB ON LB.ID = DL.LABEL_ID
      WHERE DL.STATE = 3
      ORDER BY DL.TIME DESC
    `)

    yield { type: "phase", name: "ehviewer.queried", data: { count: rows.length } }

    let done = 0
    for (const row of rows) {
      // Legacy CATEGORY bitmask → tag ✅
      const category = EH_CATEGORIES[Math.log2(row.CATEGORY as number)] ?? "MISC"
      const title = (row.TITLE_JPN as string) || (row.TITLE as string)
      const dir   = (row.DIRNAME as string)

      yield { type: "progress", message: title, percent: done / rows.length }

      const preflight = await ctx.storage.preflight({
        normalizedTitle: normalizeTitle(title),
        contentType:     "comic",
      })

      if (preflight.action === "conflict_existing_record") {
        yield { type: "warning", message: `Skipping duplicate: ${title}` }
        done++
        continue
      }

      const registered = await ctx.storage.registerContent({
        existingContentId: preflight.existingContentId,
        contentType:       "comic",
        title,
        tags: [{ namespace: "other", tag: category }],
        sections: [],
        sourcePlatformKey: "ehviewer_import",
      })

      done++
      yield { type: "result", contentId: registered.content.id, status: preflight.existingContentId ? "repaired" : "created" }
    }
  },
})

const EH_CATEGORIES = [
  "MISC", "DOUJINSHI", "MANGA", "ARTIST CG", "GAME CG",
  "IMAGE SET", "COSPLAY", "ASIAN PORN", "NON-H", "WESTERN",
]
```

---

## ImportJob Entity Contract

**Purpose**: Runtime import orchestration record for plugin-based importers.

```
Entity: ImportJob
  id: ImportJobId (UUID v4)
  pluginKey: String (optional until importer selection completes)
  sourceType: String
  status: Enum (pending | running | completed | failed | cancelled)
  totalItems: Integer
  doneItems: Integer
  failedItems: Integer
  skippedItems: Integer
  targetCollectionId: UserCollectionId (optional)
  copyToStorage: Boolean
  errorLog: JsonArray
  startedAt: Timestamp (optional)
  completedAt: Timestamp (optional)
  createdAt: Timestamp
```

**Invariants**:
- `id` is immutable
- `pluginKey` is optional only while the runtime is selecting an importer; once `status = running`, it must identify the importer plugin or built-in official importer
- `sourceType` is adapter-owned evidence and must not make local filesystem paths canonical storage identity
- Valid status flows are `pending -> running -> completed | failed | cancelled` and `pending -> cancelled` (a queued job may be cancelled before it starts); terminal statuses must not transition back to running in place
- `startedAt` is present iff the job has entered `running`; a job cancelled from `pending` has `startedAt` absent and `completedAt` set
- `completedAt` is present only for terminal statuses
- Item counters are non-negative; `doneItems + failedItems + skippedItems <= totalItems` when `totalItems` is known
- `copyToStorage = true` means imported durable units must be registered through StorageObject/StoragePlacement, not raw file path columns
- `errorLog` must contain sanitized error summaries only; raw paths, stack traces, credentials, and source payloads are forbidden
- If `targetCollectionId` is present, the job may add completed content to that collection only after canonical Content writes succeed

---

## DB: Plugin Tables

> **Target fragments.** Canonical home for all tables is `02_DATABASE_SCHEMA.md` (the single schema authority). The blocks below are pending consolidation there and are not independently authoritative. `source_repositories` / `source_package_artifacts` live canonically in 02 **with full verification evidence** — do not redefine them here.

```sql
CREATE TABLE installed_plugins (
  id                 TEXT PRIMARY KEY,
  plugin_key         TEXT NOT NULL UNIQUE,
  manifest_json      TEXT NOT NULL,
  artifact_id        TEXT NOT NULL,
  source_platform_id TEXT REFERENCES source_platforms(id) ON DELETE RESTRICT,
  state              TEXT NOT NULL CHECK (state IN (
    'installed','activating','active','disabled',
    'update_available','load_error','uninstalling'
  )),
  isolation_level    TEXT NOT NULL DEFAULT 'full'
    CHECK (isolation_level IN ('full','shared','native')),
  last_activated_at  TEXT,
  last_error_code    TEXT,
  last_error_msg     TEXT,
  restart_count      INTEGER NOT NULL DEFAULT 0,
  config_json        TEXT NOT NULL DEFAULT '{}',
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);

CREATE TABLE plugin_reader_modes (
  plugin_key             TEXT NOT NULL REFERENCES installed_plugins(plugin_key) ON DELETE CASCADE,
  mode_id                TEXT NOT NULL,
  display_names_json     TEXT NOT NULL,
  content_types_json     TEXT NOT NULL,
  component_url          TEXT NOT NULL,
  settings_schema_json   TEXT NOT NULL,
  settings_defaults_json TEXT NOT NULL,
  created_at             TEXT NOT NULL,
  PRIMARY KEY (plugin_key, mode_id)
);

CREATE TABLE import_jobs (
  id                   TEXT PRIMARY KEY,
  plugin_key           TEXT,    -- which importer handled this
  source_type          TEXT NOT NULL,
  status               TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','completed','failed','cancelled')),
  total_items          INTEGER NOT NULL DEFAULT 0,
  done_items           INTEGER NOT NULL DEFAULT 0,
  failed_items         INTEGER NOT NULL DEFAULT 0,
  skipped_items        INTEGER NOT NULL DEFAULT 0,
  target_collection_id TEXT REFERENCES user_collections(id) ON DELETE SET NULL,
  copy_to_storage      INTEGER NOT NULL DEFAULT 1,
  error_log_json       TEXT NOT NULL DEFAULT '[]',
  started_at           TEXT,
  completed_at         TEXT,
  created_at           TEXT NOT NULL
);

CREATE TABLE export_jobs (
  id            TEXT PRIMARY KEY,
  plugin_key    TEXT,
  content_ids_json TEXT NOT NULL,
  format        TEXT NOT NULL,
  output_format TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','completed','failed','cancelled')),
  output_path   TEXT,
  error_msg     TEXT,
  started_at    TEXT,
  completed_at  TEXT,
  created_at    TEXT NOT NULL
);

-- source_repositories and source_package_artifacts are defined canonically in
-- 02_DATABASE_SCHEMA.md (§ Plugin & Package tables). DO NOT redefine them here.
-- The canonical source_package_artifacts carries install-time verification evidence:
--   verification_tier CHECK ('official','community','custom','unverified')
--   + publisher_key_fingerprint + signature_digest
-- Those fields MUST be persisted and MUST NOT be dropped; "signatureValid" must
-- never be stored as a mutable boolean. See 08_SOURCE_PACKAGE_LIFECYCLE.md for the
-- verification-tier state machine. trust_tier vocab = 'official','community','custom'.
```

---

## Provider Result Types

```typescript
interface ContentListResult {
  items:       ContentListItem[]
  total?:      number
  hasMore:     boolean
  nextCursor?: string
}

interface ContentListItem {
  sourceContentId: string
  title:           string
  coverUrl?:       string
  authors?:        string[]
  tags?:           RawSourceTag[]
  status?:         string
  updateTime?:     string
  description?:    string
  contentType?:    ContentType
}

interface ContentDetailResult {
  sourceContentId:     string
  title:               string
  coverUrl?:           string
  alternativeTitles?:  Array<{ title: string; locale?: string }>
  authors?:            Array<{ name: string; role: string; profileUrl?: string }>
  description?:        string
  tags?:               RawSourceTag[]
  status?:             string
  language?:           string
  releaseYear?:        number
  externalIds?:        Record<string, string>
  contentType?:        ContentType
}

interface SectionListResult {
  sections: SectionListItem[]
}

interface SectionListItem {
  remoteSectionId: string
  sectionNumber?:  string
  title?:          string
  language?:       string
  uploadTime?:     string
  sourceOrder?:    number
  isPremium?:      boolean
  group?:          string
}

interface UnitListResult {
  units: UnitItem[]
}

interface UnitItem {
  url:       string
  unitType:  ContentUnitType
  width?:    number
  height?:   number
  mimeType?: string
}

interface RawSourceTag {
  namespace?: string
  tag:        string
  score?:     number
  isNegative?: boolean
}
```

---

## Plugin Error Codes

```typescript
// @venera/events/src/errors.ts

const ErrorCodes = {
  // Network
  NETWORK_TIMEOUT:          "NETWORK_TIMEOUT",
  NETWORK_BLOCKED:          "NETWORK_BLOCKED",
  RATE_LIMITED:             "RATE_LIMITED",
  AUTH_REQUIRED:            "AUTH_REQUIRED",
  AUTH_FAILED:              "AUTH_FAILED",

  // Provider parse errors
  PARSE_CONTENT_LIST:       "PARSE_CONTENT_LIST",
  PARSE_CONTENT_DETAIL:     "PARSE_CONTENT_DETAIL",
  PARSE_SECTIONS:           "PARSE_SECTIONS",
  PARSE_UNITS:              "PARSE_UNITS",
  SELECTOR_NO_MATCH:        "SELECTOR_NO_MATCH",
  INVALID_RETURN_TYPE:      "INVALID_RETURN_TYPE",

  // Importer errors
  IMPORT_UNSUPPORTED_FORMAT: "IMPORT_UNSUPPORTED_FORMAT",
  IMPORT_COPY_FAILED:        "IMPORT_COPY_FAILED",
  IMPORT_CONFLICT_STORAGE:   "IMPORT_CONFLICT_STORAGE",
  IMPORT_CONFLICT_RECORD:    "IMPORT_CONFLICT_RECORD",
  IMPORT_MISSING_FILES:      "IMPORT_MISSING_FILES",
  IMPORT_EXTRACT_FAILED:     "IMPORT_EXTRACT_FAILED",
  IMPORT_METADATA_INVALID:   "IMPORT_METADATA_INVALID",

  // Export errors
  EXPORT_UNSUPPORTED_FORMAT: "EXPORT_UNSUPPORTED_FORMAT",
  EXPORT_WRITE_FAILED:       "EXPORT_WRITE_FAILED",

  // Storage errors
  STORAGE_GET_FAILED:        "STORAGE_GET_FAILED",
  STORAGE_PUT_FAILED:        "STORAGE_PUT_FAILED",
  STORAGE_AUTH_FAILED:       "STORAGE_AUTH_FAILED",
  STORAGE_QUOTA_EXCEEDED:    "STORAGE_QUOTA_EXCEEDED",
  FILE_ACCESS_DENIED:        "FILE_ACCESS_DENIED",

  // Runtime
  RUNTIME_VERSION:           "RUNTIME_VERSION",
  API_LEVEL_MISMATCH:        "API_LEVEL_MISMATCH",
  API_REMOVED:               "API_REMOVED",
  PERMISSION_DENIED:         "PERMISSION_DENIED",
  PLUGIN_NOT_INITIALIZED:    "PLUGIN_NOT_INITIALIZED",
  PLUGIN_UNKNOWN_ERROR:      "PLUGIN_UNKNOWN_ERROR",
} as const
```

---

## Audit Stream: Plugin Events

```typescript
// @venera/events/src/streams/plugin.ts

export const PluginEvents = {
  // Lifecycle
  INSTALLED:            "plugin.installed",
  ACTIVATED:            "plugin.activated",
  DEACTIVATED:          "plugin.deactivated",
  UPDATED:              "plugin.updated",
  UNINSTALLED:          "plugin.uninstalled",
  LOAD_ERROR:           "plugin.load_error",
  WORKER_CRASHED:       "plugin.worker_crashed",

  // Network
  FETCH_COMPLETED:      "plugin.fetch.completed",
  FETCH_BLOCKED:        "plugin.fetch.blocked",
  FETCH_RATE_LIMITED:   "plugin.fetch.rate_limited",

  // Import
  IMPORT_STARTED:       "plugin.import.started",
  IMPORT_COMPLETED:     "plugin.import.completed",
  IMPORT_FAILED:        "plugin.import.failed",
  IMPORT_SKIPPED:       "plugin.import.skipped",

  // Export
  EXPORT_STARTED:       "plugin.export.started",
  EXPORT_COMPLETED:     "plugin.export.completed",
  EXPORT_FAILED:        "plugin.export.failed",
} as const
```
