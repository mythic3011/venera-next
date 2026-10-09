# Remote Reading Assets and Canonical Page Pipeline (Design Proposal)

> Status: PROPOSED — 2026-10-09. Not merged into canonical 00–11 specifications; implementation is not claimed. Companion: [13_PLUGIN_DATA_LOCALES_TRANSLATION.md](13_PLUGIN_DATA_LOCALES_TRANSLATION.md).
>
> Context: Existing 05_PLUGIN_SYSTEM defines a first-class executable JavaScript scraper via defineProvider(search/getDetail/getSections/getUnits/resolveUnitUrl); existing 07_FEATURES defines UC-REMOTE-001. Neither should be replaced by a catalog-only adapter.

## Ruling

The reader accepts stable canonical ContentUnit IDs and typed asset descriptors from these peer paths:

| Path | Discovery | Asset | Decoder |
|---|---|---|---|
| JS website source / EhViewer-like gallery | JS sandbox scraper for search, metadata, chapters, ordered image pages | Provider-specific, runtime-authorized image-request reference | Image |
| WebDAV image directory | First-party scoped PROPFIND | Remote image reference | Image |
| WebDAV / OpenList WebDAV CBZ | First-party scoped PROPFIND | Remote archive + entry evidence | ZIP index + Image |
| OPDS 1.2 / OPDS 2.0 | Feed navigation + acquisition links | Actual advertised acquisition asset | Relevant handler |
| Explicit HTTP(S) CBZ | User-configured remote archive | Archive + entry evidence | ZIP index + Image |
| Local image/CBZ | Existing bundled importer | Local owned storage | Existing importer/decoder |

No WebDAV, OPDS or archive machinery is required for a JS scraper with a direct ordered list of images. Conversely a generic DAV reader does not require an executable source plugin.

## Ownership and interfaces

~~~text
UI reader intent
 -> ResolveReaderTarget -> canonical ContentSection/ContentUnitOrder/ContentUnit
 -> AssetResolver
      -> ProviderImageResolver (JS provider sandbox and PluginProxy)
      -> FirstPartyRemoteTransport (configured WebDAV/OPDS/HTTP resources)
      -> ArchiveIndex/EntryDecoder (ZIP/CBZ over verified byte ranges)
      -> OwnedStorageResolver (optional offline verified placement)
 -> Image decoder and viewer
 -> ReadingSession(unitId)
~~~

- JS plugins own website-specific request constructors, parsers, pagination, chapter/page discovery, and short-lived image URL resolution. Runtime owns accounts, immutable request-time credentials/header snapshots, network execution, retries, cooldowns, response classification, diagnostics and cache policy. See source-runtime-account-request-policy.md.
- PluginProxy retains public-only, declared-domain SSRF controls. A user-explicit first-party LAN/NAS/Tailscale mount may receive narrowly scoped private origin access; never lend this privilege to JS providers.
- Only verified owned bytes obtain StorageObject/StoragePlacement authority. A third-party external archive itself is a RemoteResource, not automatically an owned StoragePlacement. Offline acquisition creates and commits StorageObject + Placement transactionally.
- ReadingSession.unitId remains the sole persisted progress authority; location, signed URL, filename, source page ordinal and archive-entry offset are evidence, not canonical identity.
- Extend existing UC-REMOTE-001, not create another independent unit allocator. Every unit and active-order reconciliation must be atomic and serialized per section. Weak page evidence (ordinal/unstable URL) must not silently rebind saved position.

## Proposed remote binding model

A generic RemoteMount is an instance-scoped first-party endpoint with immutable mount ID, kind (webdav/opds1/opds2/http_collection), sourcePlatform linkage, schema-versioned non-secret config, secretRef, egress policy and lifecycle. RemoteResource represents a mount-scoped remote image/archive with opaque stable resource key and observed validator epoch. RemoteUnitBinding holds Unit-to-resource/provider evidence of one kind: provider_image, remote_image or archive_entry. Multiple bindings per unit require an explicit authority/failover arbitration contract before implementation.

Every provider gets its existing stable SourcePlatform identity. A RemoteMount obtains its own namespaced SourcePlatform; do not conflate different DAV accounts or endpoints into one identity. Never persist short-lived signed URLs, raw cookies or authorization headers as provenance.

## Provider image lifecycle

1. getUnits(remoteSectionId) in restricted JS Worker returns ordered image candidates and optional stable provider page references.
2. Materializer validates and matches evidence, commits units and complete active order transactionally.
3. AssetResolver asks runtime to construct an approved image request bound to the immutable account+header profile revision.
4. Runtime checks target domain/port/IP, redirect hops, request headers, response status/type/size. Referer-dependent image CDNs must be explicitly allowed; raw plugin image URLs are not network authority.
5. Decode and display selected image; cancellable adjacent-page prefetch has lower priority.
6. Persist only actual reader navigation. Expired signed URLs prompt bounded provider re-resolution; failure returns typed state, not a changed position.
7. Provider reorder, missing stable page refs or account changes never silently reuse an old Unit for unverified new bytes.

## Remote ZIP/CBZ byte ranges

Probe actual 206 Content-Range behavior (do not rely on Accept-Ranges alone). Under a stable validator, fetch EOCD/ZIP64, central-directory spans, local header and only the selected compressed entry. Validate offset/length, method, decompression budgets, file names, duplicate ambiguities and decoded image magic/CRC. 200-for-Range, 416, validator change, malformed index and password-protected entries are explicit errors. A bounded, consent-aware full-object fallback can be offered; do not mislabel it as streaming. Weak/missing validators require conservative revalidation.

## Security and availability

- Plugin URL/DOM/translation content never enters unguarded HTML sinks; data and executable code have distinct trust levels.
- All HTTP and DAV requests are bounded, aborted on navigation, and account snapshots cannot mutate under in-flight requests.
- Show precise auth-required, unreachable, unsupported-range, changed-version, invalid-image and offline states.
- OPDS is catalog/acquisition only; no assumption that OPDS servers expose per-page streaming.
- Index/decoded-page cache entries are invalidated by resource-version epoch; offline verified user-selected copies are not normal evictable cache.
- Preserve M1 local-only scope. Design/security gates belong in M3.0; all online paths are M3 and later.

## Acceptance gates

1. JS provider obtains ordered pages, Referer-required CDN, expires URL, retries under one account snapshot, and saves accurate Unit position.
2. WebDAV image directory and OpenList WebDAV CBZ read online through the same reader; 206 path does not fetch full archive.
3. OPDS acquisition type routes to the appropriate handler; an unsupported link is rejected clearly.
4. Changed bytes/order cannot silently remap a previously saved Unit ID.
5. Plugin cannot use user-approved private WebDAV network privileges.
6. Airplane-mode offline verified copy reopens from the same canonical Units.
7. Tests cover 200-for-Range, malformed 206, ZIP64, ZIP bomb, symlink/traversal, private SSRF, redirect leaks, cancellation and duplicate concurrent materializations.

## Adoption

Update 01_ENTITIES, 02_DATABASE_SCHEMA, 03_USE_CASES, 04_PACKAGES_AND_PIECES, 05_PLUGIN_SYSTEM, 07_FEATURES, 09_OBSERVABILITY, 11_MILESTONES and SUMMARY through a reviewed cross-file change. This document is a proposal, not a second canonical authority.

References: [HTTP RFC 9110](https://www.rfc-editor.org/rfc/rfc9110), [WebDAV RFC 4918](https://www.rfc-editor.org/rfc/rfc4918), [OPDS 1.2](https://specs.opds.io/opds-1.2), [OPDS 2.0](https://specs.opds.io/opds-2.0).
