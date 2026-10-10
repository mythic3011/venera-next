# v2 Plugin SDK: Data-Driven Sources, Security, Lazy Localisation and Page Translation

> **Status: design proposal (2026-10-09)**. This is not an implemented API and does not override the canonical design in 00–11. Companion: [12_REMOTE_READING_ACCESS.md](12_REMOTE_READING_ACCESS.md).
>
> **Evidence:** `mythic3011/venera-configs` already has `plugins/*/plugin.config.json`, `shared/families/{copy_like,mh_like,self_hosted_library}`, `shared/features/*`, a build manifest, and script-level unsafe-runtime audit. However E-Hentai keeps locale tables in `src/i18n.js` plus legacy `i18n/ehentai.json`; nhentai embeds `TRANSLATION_DATA` and a large tag dataset in its JS source; E-Hentai implements per-source inflight queue/cooldown in `request-client.js`; Komga maintains its own reference-data refresh. These are examples of overlapping state and contracts, not evidence that shared helpers do not exist.

## 1. Principles and decisions

1. **Data-driven first, JS escape hatch second.** Descriptors expressed in versioned JSON, not arbitrary executables for declarative cases. Complex scraping, signing, obfuscation and dynamic page resolution may still require restricted JS hooks.
2. **Executable JS provider remains first-class.** As per 05's `defineProvider`, it can search, parse metadata, chapters and ordered image pages. It must not be reduced to a discovery-only feed.
3. **Shared runtime SDK owns common mechanics.** Plugins declare parameters; SDK owns HTTP/session/headers/cookies/retry/rate/cooldown/pagination/DOM parsing input validation/typed errors/cache and translation loading. No plugin constructs its own security policy.
4. **Do not download every dictionary.** Separate UI locales, source metadata lexicon, canonical tag taxonomy, and actual comic-page OCR/translation. Lazy-load by user language + source + namespace + reader operation; disable features without acquiring their packs.
5. **Versioned, signed, atomic data subscriptions.** AdGuard-style index + scoped packs + checksum/signed manifest + caching + offline last-known-good + update/delta support, no arbitrary code from data files.
6. **UI/renderer and JS runtime are separate trust domains.** DOM/HTML/translated payloads stay data; no plugin-defined unsanitized HTML/JS ever executes in the reader or admin UI.

## 2. Capability model and runtime routing

Three plugin tiers, with one shared asset reader from 12:

- `declarative`: JSON definitions, static endpoint builders (templated with typed escaping), CSS/JSONPath selectors, JSON mapping, bounded regex if supported; no JS execution.
- `sdk_hooks`: declarative descriptor plus source-specific JS functions running in constrained worker with message-only runtime APIs.
- `full_compat`: legacy JS wrapper for migration, same minimum network/credential controls; mark exact reduced guarantees and expiry, not a permanent unrestricted mode.

SDK capabilities include `discover/search`, `detail`, `sections`, `units`, `image.resolve`, `account.validate`, `metadata.map`, `tag.map`, `locale.lookup`, `page.ocr`, `page.translate`, and `settings.schema`. A plugin declaring permission to parse images does not thereby get access to every account, raw credentials, DOM or remote host.

Untrusted JS may not call arbitrary `eval`, `new Function`, Electron/Node/Dart host APIs, filesystem, environment, DB, raw CookieJar, cross-plugin config stores, unapproved native modules or unrestricted network. Build-time text scanning is defense-in-depth **not** a sandbox. Use an isolate/process with hardened capability RPC and measured resource/time budgets.

## 3. Declarative package and concrete example

The schema below is proposed. Do **not** assume existing venera-configs loader understands it.

~~~json
{
  "contractVersion": 2,
  "providerKey": "example_gallery",
  "pluginVersion": "2.0.0",
  "kind": "website_scraper",
  "capabilities": ["search", "detail", "sections", "units"],
  "network": {
    "allowedOrigins": ["https://example.org", "https://images.example.org"],
    "methods": ["GET"],
    "headerProfiles": ["webPage", "imageReferer"]
  },
  "parsing": {
    "engine": "html-css",
    "search": {
      "request": {"method": "GET", "path": "/search", "query": {"q": "$query"}},
      "items": ".result-item",
      "fields": {
        "id": {"selector": "a", "attribute": "href", "transform": "extractWorkId"},
        "title": {"selector": ".title", "read": "text"},
        "cover": {"selector": "img", "attribute": "data-src", "transform": "resolveUrl"}
      },
      "pagination": {"kind": "next_link", "selector": "a.next", "maxPages": 20}
    },
    "units": {
      "items": ".page",
      "fields": {
        "providerPageRef": {"attribute": "data-page-id"},
        "image": {"selector": "img", "attribute": "data-src", "transform": "resolveUrl"}
      }
    }
  },
  "localisation": {
    "defaultLocale": "en",
    "namespaces": ["ui", "metadata", "tags"],
    "packIndexRef": "packs/index.json",
    "fallback": {"zh-HK": ["zh-TW", "zh-Hant", "en"], "zh-TW": ["zh-Hant", "en"]}
  },
  "pageTranslation": {
    "enabledByDefault": false,
    "languages": ["ja", "zh-Hant", "en"],
    "pipeline": ["ocr", "detect_language", "translate", "overlay"],
    "engines": "runtime_selected"
  }
}
~~~

`extractWorkId` and `resolveUrl` are **runtime-registered, allowlisted transform identifiers**, not JS strings to `eval`. No source-defined arbitrary expression or unbounded regular expression runs inside a JSON field. Inputs, selector grammar, size, max depth and pagination must be validated.

Only site-specific fields stay in a provider descriptor. Rate-limit policy, account state, URL policy, retry and diagnostics are SDK infrastructure; website-specific exceptional signing may be a granted bounded hook, not copied boilerplate.

## 4. Four distinct language problems

| Concern | Example | Authority | Load trigger | Cache |
|---|---|---|---|---|
| App UI localisation | Reader buttons, settings | Venera core i18n | selected UI locale / screen | installed core or small scoped UI pack |
| Plugin UI localisation | "Search", "Image quality" | provider translation namespace | source settings / screen | `providerKey,locale,namespace` |
| Metadata/tag translation | genres, tags, author-role label, category | canonical taxonomy + source-specific mapping | tag/filter details and locale choice | shard by source/namespace/locale |
| Comic page translation | words inside image panels / text balloons | OCR + Translation pipeline, **not** dictionary-only localisation | reader action or opted-in page auto-translate | page+engine+language+settings scoped |

A tag dictionary cannot translate arbitrary words in an image. Actual page translation requires OCR/text-region detection, language detection, translation and geometry-safe overlay/redraw. Source image bytes remain immutable. Translation overlays are derived data with explicit language/provider/model/version provenance.

Optional OCR models/language packs must not download when only changing UI language or browsing a collection. Respect device/network preference and per-pack disk budgets.

## 5. Subscription packs: AdGuard-style, without copying security flaws

~~~text
Source repository or trusted local bundle
  -> signed pack index (scope, locale, namespace, version, minSDK, digest, size)
  -> on-demand pack request
  -> verify signature / trusted index binding + sha256 + schema + decompression limits
  -> staged immutable cache
  -> atomic activation
  -> last-known-good fallback on errors
  -> garbage collection under disk budget
~~~

Minimal pack-index shape (logical):

~~~json
{
  "schemaVersion": 1,
  "providerKey": "ehentai",
  "release": "2026.10.09",
  "packs": [
    {"id":"ui-zh-HK","locale":"zh-HK","namespace":"ui","version":"3","format":"json","path":"packs/ehentai/ui.zh-HK.json","sha256":"<64-hex-digest>","bytes":4096},
    {"id":"tags-zh-Hant","locale":"zh-Hant","namespace":"tags","version":"8","format":"json","path":"packs/ehentai/tags.zh-Hant.json","sha256":"<64-hex-digest>","bytes":98274}
  ]
}
~~~

**Example values are illustrative, not verified packages.** The signed release index must authorize pack hashes and scope; signing arbitrary per-provider remote data with no trust root is not sufficient. Enforce `locale`, `providerKey`, `namespace`, revision and path containment, and canonical BCP 47 tags internally (`zh-HK`, not inconsistent `zh_HK`/ `zh_CN` aliases). Enforce per-pack/per-namespace caps, bounded expansion and parse time.

Runtime should:
- Load `ui` only when a source settings/label actually requires the namespace; `tags` for selected tag/genre view, not upon plugin registration.
- Use locale fallback `zh-HK -> zh-TW -> zh-Hant -> en` as a **product-defined** fallback, not automatic linguistic equivalence. Allow zh-HK overrides.
- Use `ETag`/conditional GET for freshness and `SHA-256` for digest verification; versioned immutable cache keys. Failed update never replaces working pack. Download in chunks only if bandwidth/storage settings justify it.
- Support `enabled=false` per namespace and per source. No automatic new-language install without intent/opt-in.
- Use index summaries or Bloom filters only as **optional** fast negative lookups; false positives cannot change translation correctness. For small dictionaries, direct map lookup is simpler.
- Prefer full signed pack replacement initially; patch/delta complexity ships only with reproducible digest-verified reconstruction and rollback.
- Keep exact fallback/update schedule and offline TTL explicit; no silent infinite-lifetime security rules.

Suggested cache key: `(packIdentity, packVersion, providerKey, locale, namespace, contentDigest)`. Never key only on filename. Cache size and last-used policy are runtime-owned; downloaded user-pinned offline page translation may have its own retention policy.

## 6. XSS and untrusted text boundaries

**Threat sources:** scraped HTML, site metadata, title/description, source-defined labels, translation packs, markdown, OCR output, subtitle-like text, and JS plugin return values. All are **untrusted text** unless proven otherwise.

**Rules:**
1. Model data as plain typed strings, not HTML. Render via framework's escaped text nodes. Never interpolate site/pack/OCR fields into `innerHTML`, `dangerouslySetInnerHTML`, WebView `loadHtmlString` or a JS URL.
2. When formatting markup is essential, parse to a **very small allowlisted structured AST** (e.g. paragraph, line break, bold, italic, safe link). Sanitize and validate links by scheme/host; no iframe/script/style/event handlers/foreignObject. Render AST as platform-native components, not a string of HTML.
3. Enable strict CSP (including no unsafe-eval), Trusted Types where supported, iframe/webview origin isolation and sandbox, disallow top-level navigation and bridge access from source-supplied HTML. CSP is supplementary, not a substitute for escaping and isolation.
4. Plugin workers receive parsed/sanitized DOM snapshots or restricted HTML parsing APIs, not a privileged document object belonging to Venera's UI. Avoid regex-driven `<script>` execution; embedded site JSON extraction must parse data, never run its code.
5. A translation pack is **never executable code**. JSON transforms reference known pure transform IDs only; no template expressions able to access globals, prototype chains, raw HTML or runtime secrets. Validate keys such as `__proto__` and `constructor` against prototype pollution.
6. OCR and page translation output always passes the same untrusted-text renderer. Text overlays are limited to bounded coordinates, glyph counts and styling. No HTML in translated comic balloons.
7. Treat translations and locale metadata as potential phishing/UI-spoofing inputs: isolate provider namespace, preserve security-sensitive core prompts/permission wording in trusted core translations, bound string lengths and bidi control sequences.
8. Prevent stored XSS across saved metadata, search history, exports and hosted sync—validate on ingress and encode on **every output sink**.
9. Secrets or signed image URLs never enter HTML markup or plugin-visible arbitrary messages. Plugin errors and diagnostics are redacted before UI.
10. Test malicious source title, malicious translation string, hostile SVG/image metadata, markdown, malicious URL and script-literal parsing against all UI surfaces and platform-specific WebViews.

XSS in a plugin and HTML escaping are not the only risks: an unrestricted executable JS plugin also poses arbitrary host API and network-exfiltration risks. A regex audit of `eval` is not a proven sandbox.

## 7. Page translation pipeline and privacy

~~~text
Current rendered image (read-only source asset)
  -> optional bounded crop/page image acquisition
  -> detect regions + OCR text
  -> infer/choose source language
  -> translate into chosen target locale
  -> layout overlay with confidence and bounding boxes
  -> reader composes non-destructive overlay over original image
~~~

The default mode is **OFF**; when enabled, process only current page and optional limited adjacent prefetch. Lazy-load OCR/translation models or remote engine only on first page-translate action; never on plugin initialization, UI locale change or normal scraping. A remote AI translation engine requires informed opt-in because comic images/text may be sent to a third party; allow local-only mode and per-source/network restrictions.

Cache identity must include `contentUnitId`, verified image fingerprint or resource validator epoch, crop/region provenance, OCR engine/version, translator/model/version, source/target languages and options. A different comic page, locale or image version must never reuse an overlay incorrectly. No mutation to original image or ReadingSession on translation failure; show original content.

Distinguish:
- script conversion (OpenCC) for existing text;
- dictionary/metadata localisation for known labels/tags;
- machine translation of extracted arbitrary text;
- optional image redraw/inpainting (future, costly, separate capability/consent).

## 8. Shared SDK migration plan (venera-configs -> venera-next)

Baseline on `venera-configs`:
- `shared/families/copy_like` and `shared/features/copy_like` already factor request/category/search commonality.
- `shared/families/self_hosted_library` and `shared/features/self_hosted/*` already factor Komga/LANraragi-style helpers.
- `plugins/ehentai/src/i18n.js` and legacy `i18n/ehentai.json` duplicate translation source roles.
- `plugins/nhentai/src/index.js` contains inline locale tables and large tag mappings.
- `plugins/ehentai/src/request-client.js` owns in-plugin queue/inflight/cooldown logic that should be runtime-owned.
- `scripts/audit/unsafe-runtime-code.js` does regex checks for eval/new Function: retain for lightweight detection but do not use as execution boundary.

Target layering:
~~~text
venera-configs/
  plugins/<key>/plugin.config.json   # small declarative descriptor
  plugins/<key>/src/*                # site-specific JS hooks only when needed
  data/locales/<key>/<locale>/*.json
  data/taxonomy/<key>/*.json
  recipes/<family>/*.json            # parameter overrides, not duplicated logic
  tests/contracts/<key>/*
  dist/...                           # reproducible signed artifacts and indexed data packs

venera-next/
  packages/sdk/src/contracts
  packages/sdk/src/recipes           # vetted built-in family implementations
  runtime/core/src/ports             # immutable network, account, config, parser ports
  runtime/core/src/application       # use cases, orchestration, AssetResolver
  runtime/adapters/...               # actual HTTP, sandbox, secret storage, OCR, storage
~~~

Logical target only: repo paths are illustrative until package-layout review.

### Test/rollout sequence

**P0 — safety contracts:** typed remote display data, sanitized text/AST rendering, JS host API denial, SSRF isolation, immutable request-time auth, schema tests, no capability escalation by JSON.

**P1 — low-risk shared recipes:** self-hosted library and copy-like families, request/cache/pagination unification. Prove code shrink, consistency and behavior equivalence with fixture tests.

**P2 — packs:** move E-Hentai and nhentai UI locales into namespace/locale JSON; lazy pack resolver and fallback; migrate the legacy JSON by explicit aliasing without dual mutable authority; extract large tags into scoped data packs.

**P3 — structured scraping:** create one declarative selector-based example and one JS-hook scraper; both produce the same typed ContentUnit asset descriptors without hardcoded runtime flow.

**P4 — page translation:** opt-in OCR/translation overlay pipeline and cache, with privacy/local-only tests. Heavy models and every locale dictionary remain uninstalled until asked for.

Acceptance criteria:
- no plugin executes when only opening the source catalog/locale index;
- switching zh-HK/zh-TW/en downloads only required namespaces, with offline last-known-good and atomic rollback;
- no duplicate queue/cooldown/account-credential ownership in individual providers;
- all scraped and translated HTML payloads remain inert through every reader/admin surface;
- multiple plugins can use the same versioned SDK recipe while retaining independent endpoint/selector data;
- a JS gallery scraper still supplies ordered images, Referer/CDN requests and typed failures;
- stale/expired source pack or OCR result never changes canonical Unit identity;
- failures, latency, byte budget, and cache hit/miss are observable without logging secrets/raw URLs/titles.

## 9. Canonical change map (review before adoption)

- `05_PLUGIN_SYSTEM.md`: declarative plugin format, built-in recipes, hook capabilities, page metadata and separated data-pack trust.
- `04_PACKAGES_AND_PIECES.md`: i18n/translation/cache/OCR ports and ownership.
- `06_SECURITY_AUTH_RECOMMENDATION.md`: XSS and WebView/JS worker isolation, data/config scope and runtime-only credential policies.
- `07_FEATURES.md`: optional page translation flow, page cache and lazy fetch.
- `09_OBSERVABILITY.md`: redacted pack verification/load and translation failures.
- `08_SOURCE_PACKAGE_LIFECYCLE.md`: package/data-pack artifact signing, atomic updates, rollback and channel/version policy.
- `11_MILESTONES.md`: JS/Data SDK and metadata localization before page OCR/translation.
- `SUMMARY.md`: accepted invariants only, after canonical cross-file updates.

**Design review required:** exact trust/signing authority for separately updated data packs; OS-specific DOM and worker sandbox implementation; upstream recipe API stability; consent policy for remote OCR; data-retention/encryption; secure rich-text allowlist; pack update cadence; whether provider-localised labels participate in canonical taxonomy or remain presentation-only.
