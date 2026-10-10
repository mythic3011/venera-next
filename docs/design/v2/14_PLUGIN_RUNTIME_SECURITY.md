# v2 Plugin SDK Security: Capability Broker and Attack-Chain Threat Model

> **Status: proposed security/design contract — 2026-10-09.**
>
> This is a companion to [12_REMOTE_READING_ACCESS.md](12_REMOTE_READING_ACCESS.md) and [13_PLUGIN_DATA_LOCALES_TRANSLATION.md](13_PLUGIN_DATA_LOCALES_TRANSLATION.md). It does **not** supersede canonical v2 contracts until adopted in their authoritative files. The SDK/API types are **proposals**, not existing implementation.
>
> **Core ruling:** JS plugins may run site-specific parsing/scraper hooks, but cannot obtain direct privileged host APIs. The only cross-boundary path is a runtime-owned **typed, capability-scoped RPC broker**, with every request authorized at execution time. This is not "disabling JS": it is removing ambient authority while keeping the first-class executable scraper model.

## 1. Comparison: Claude Agent SDK is a pattern, not a security dependency

Official primary-source references, checked 2026-10-09:

- [Configure permissions — Claude Agent SDK](https://code.claude.com/docs/en/agent-sdk/permissions): the documented order is **hooks → deny → ask → permission mode → allow → canUseTool**. A bare disallowed tool is removed from the exposed context; a scoped `Bash(rm *)` deny is matched as written and does not necessarily match `/bin/rm`. Broad allow and bypass permissions can shadow `canUseTool`. An unconditional PreToolUse policy check can cover tool calls before earlier approvals.
- [Intercept with hooks](https://code.claude.com/docs/en/agent-sdk/hooks): hook callbacks inspect/block calls but are not a substitute for isolation.
- [Securely deploying AI agents](https://code.claude.com/docs/en/agent-sdk/secure-deployment): separate privileged credentials and network access outside the untrusted worker; a proxy brokers access; OS filesystem/network sandboxing is independent of an application permission check. Its command parsing includes AST work, **which must not be confused with the string-pattern matching of permission rules**.
- [OWASP XSS Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet): encode for the actual output context, sanitize only if rich HTML is essential, treat CSP/Trusted Types as additional defenses.
- [OWASP SSRF Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html): normalize/validate structured network destinations, enforce allowlists, do not automatically trust redirects.

**What transfers:** default-deny; remove capabilities before execution; deny wins; structured argument verification; independent OS sandbox; child/plugin grants may only attenuate; always validate at the runtime boundary.

**What does not transfer literally:** an LLM produces a tool-call request; a Venera third-party JS plugin already executes code. A `PreToolUse`-style callback **inside the plugin or its SDK wrapper is not a trusted gate**. Place mandatory enforcement inside the host/runtime broker with trusted caller attribution, outside the plugin isolation boundary.

## 2. Assets, principals and trust boundaries

| Trust domain | Examples | Authority it may have |
|---|---|---|
| Core runtime + broker | policy engine, app-owned storage, credential manager, canonical DB | privileged; must validate all untrusted requests |
| Verified artifact + operator grants | signed JS package + exact install-time permission record | **identity and bounded consent**, never intrinsic safety; signing != harmless |
| Sandbox worker | website JS scraper, selector recipes, optional signed hooks | compute/parse + only negotiated RPC operations; no ambient host/network/filesystem |
| Untrusted remote bytes | HTML, JSON, image URLs, OPDS, WebDAV XML, archive entries | data only, never instructions/permissions |
| Data packs | locales, tag dictionaries, mapping JSON, recipes | validated, immutable **data**; cannot declare new executable behavior |
| Renderer | library/list/detail/reader UI, OCR text overlays | escape/validate untrusted fields and never expose host bridges |

Protected assets: user account secrets and cookies, WebDAV credentials, plugin install/update trust metadata, local files/DB, reading progress, signed locale pack cache, internal network, other plugins' namespaces, reader/UI process, telemetry privacy.

**Boundary A:** source website → sandbox parser. **Boundary B:** plugin worker → broker RPC. **Boundary C:** broker → network/credential/data ports. **Boundary D:** plugin/parser/locale output → canonical model and UI rendering. **Boundary E:** package/locale subscriptions → signed updater/cache. Every boundary validates its own invariants.

## 3. Plugin SDK is an interface, never raw direct host calls

The plugin's `ctx` is a **facade of RPC request methods**; the implementation in the untrusted worker only serializes typed messages to the host. The host's `Broker` selects and checks its trusted `PluginSession`; neither `pluginKey` nor `accountId` passed by JS is caller authority.

**Proposed example — deliberately no arbitrary `RequestInit` or filesystem/DB object:**

~~~ts
// Shared type-only plugin SDK contract, NOT a host object:
type PluginRuntimeApi = Readonly<{
  net: {
    request(input: {
      endpointRef: string;                   // granted named endpoint / template
      method: "GET" | "POST";                 // further restricted by operation grant
      pathParams?: Record<string, string>;   // typed URL construction, validated
      query?: Record<string, string>;
      bodyRef?: string;                      // bounded, schema-validated request body
      headerProfileRef?: string;             // NO raw Cookie/Authorization
      responseAs: "html_snapshot" | "json" | "bytes";
    }): Promise<PluginNetworkResult>;
  };
  parse: {
    select(documentRef: string, selectorId: string): Promise<StructuredNodes>;
    jsonPath(dataRef: string, mappingId: string): Promise<unknown>;
  };
  kv: {
    get(key: string): Promise<unknown>;       // plugin-scoped, quota-bounded
    put(key: string, value: unknown): Promise<void>;
  };
  locale: {
    lookup(namespace: "ui" | "tags" | "metadata", key: string, locale: string):
      Promise<string | null>;               // lazy, scoped pack broker
  };
  diagnostics: {
    record(code: string, stage: string): Promise<void>; // typed/redacted
  };
}>;

// Example JS scraper: it MAY parse and return ordered images, not fetch arbitrarily.
async function getUnits(ctx: PluginRuntimeApi, chapterId: string) {
  const response = await ctx.net.request({
    endpointRef: "chapter",
    method: "GET",
    pathParams: { chapterId },
    responseAs: "html_snapshot"
  });
  // Plugin-specific pure parsing logic receives restricted data handles.
  return parseChapterImageCandidates(response);
}
~~~

`PluginNetworkResult` and `StructuredNodes` are typed data/opaque handles, not a live browser `window`, arbitrary fetch response object or raw privileged DOM. The host owns `endpointRef` resolution and has the final say on URL, redirect, header, account and output caps.

Bounded special-case hooks are still allowed for source-specific parsing/signature metadata but **cannot create new capabilities or read secrets**. Where an endpoint cannot be represented declaratively, a carefully scoped `net.requestCandidate` permission may be added later; it must still validate scheme/host/port/IP/redirect/method/body and must not permit arbitrary signed auth forwarding. `requestCandidate` is **not** part of the initial SDK.

**Unavailable by construction:** `fetch`, `XMLHttpRequest`, `WebSocket`, `Network.sendRequest`, `process`, `require`, `fs`, `child_process`, `Database`, `CookieJar`, unrestricted `window`/`document`, `eval` and dynamic code compilation. A JS engine may contain some language built-ins; the trusted runtime must constrain ambient bindings and native bindings, not merely check variable names in source.

A plugin's `getUnits` returns candidate pages and provenance evidence; only application use cases allocate or update ContentUnit IDs, complete orders and positions. A plugin cannot issue `saveReadingSession` or `storage.delete` on the user's behalf.

## 4. Policy evaluation: no approval bypass

~~~text
Install/enable:
  verify artifact identity + version/API compatibility + manifest schema
    -> intersect declared capabilities with runtime-supported operations
    -> explicit per-plugin/user grants (deny by default)
    -> spawn sandbox with only allowed RPC facade surface
    -> bind worker channel -> trusted PluginSession (artifact digest, plugin id,
       account-profile snapshot ref, grants revision, scopes)

Every attempted RPC:
  1. Authenticate worker channel + bind trusted plugin principal; never trust
     client-supplied pluginKey/capability/actor on its own.
  2. Parse typed message and reject unknown method/fields/oversized payloads.
  3. Apply hard mandatory denies (revoked, prohibited target, write outside scope,
     plugin-to-private-mount bridge, unverified plugin, forbidden service).
  4. Apply live grant intersection (runtime policy ∩ installed permission ∩ user
     consent ∩ per-operation scope ∩ parent/child attenuation).
  5. Validate STRUCTURED arguments, endpointRef, method, body schema, normalized
     URL/path, account snapshot revision and resource ownership.
  6. Reserve request budget / concurrency / timeout, optionally ask for elevation
     only via trusted UI. Approval is narrow, expiring, not a generic allow-all.
  7. Execute through isolated port, bind/pin DNS destination and re-check EACH
     redirect hop; inject credentials outside worker for approved origin only.
  8. Validate size, type and allowed output shape; release bounded typed result,
     redact diagnostics, record policy decision and resource use.
~~~

A denied mandatory rule **cannot** be changed to allow by Plugin JS, a permissive plugin manifest, a callback or a stale cached decision. Missing/unknown permission and policy-engine failure -> deny. If policy revision changes during async work, cancel or re-evaluate before the privileged action; approvals must not outlive revocation.

For stable installation, the SDK may omit disallowed RPC methods from the *advertised* plugin facade, but the broker must still reject forged message frames (the facade is not the enforcement boundary). Do not create a `bypassPermissions`-equivalent mode for third-party plugin execution.

**Grant intersection:** child worker/request/URL-ref grants are a strict subset of parent worker grants. A plugin with `provider.search` does not automatically receive `webdav.credentials`, `localhost.network`, `plugin.install`, `ui.html` or any other plugin's `kv`.

## 5. Attack chains and where to break them

Each chain lists a **plausible conditional exploit path**. It is not a claim that existing venera-next is currently exploitable.

### Chain A: remote metadata → DOM XSS → host bridge

~~~text
Attacker controls remote gallery title/description
 -> scraper parses HTML and returns a string
 -> canonical DB stores it as metadata
 -> unsafe UI sink interprets it as HTML
 -> injected script executes in app/webview origin
 -> script calls privileged bridge or reads exposed session data
 -> exfiltration / unauthorized local action / stored XSS persistence
~~~

Break at D: **plain-text renderer** (escaped text nodes), narrow rich-text AST when essential, fixed URL attributes, strict CSP/Trusted Types where available, safe WebView isolation without privileged `postMessage` bridge. Break at B/C: even renderer XSS cannot access untrusted plugin privileged routes or core secret APIs. Test render routes including library, search, history, notifications, translations and hosted web UI.

### Chain B: signed plugin or compromised JS → ambient capability → secrets

~~~text
Malicious/compromised source artifact executes JS
 -> raw Network.sendRequest / raw CookieJar / filesystem bound into worker
 -> reads another account or reads local app secrets
 -> sends data to attacker destination (possibly disguised as image request)
 -> persists via mutable plugin updater/config or KV credential cache
~~~

Break at worker spawn: no ambient native/file/network bindings; OS process isolation and egress restrictions (where platform supports). Break B/C: typed named-endpoint RPC, snapshot-bound credential injection outside worker, resource/namespace scope, request payload validation. Break E: signed immutable package updates and no plugin mutation of update authority. Signature identifies publisher and integrity, not author safety. **Residual risk:** a plugin may misuse data it legitimately sees or an allowed origin as an exfil route; hostname allowlisting alone cannot prove benign use. Minimize data exposure and validate request schemas and sensitive payloads.

### Chain C: source image URL → confused-deputy SSRF → LAN credentials

~~~text
Compromised parser returns URL to private OpenList/NAS origin
 -> generic image fetching code shares first-party WebDAV permission
 -> runtime follows redirect or stale DNS check
 -> privileged network request reaches internal endpoint with auth
 -> reads sensitive response or performs unintended action
~~~

Break at B/C: provider JS image fetch is **public-only PluginProxy**; trusted explicitly configured WebDAV/OPDS mount obtains **per-mount, per-origin, per-port** private networking grant. Never union them. Revalidate redirect destinations, normalize URLs, pin actual dialed IP and strip Authorization/Cookie on cross-origin hops. Require read-only operations on remote connectors; no implicit DAV write/move/delete.

### Chain D: JSON recipe / locale subscription → code or UI injection → persistence

~~~text
Attacker changes source recipe or translation dictionary
 -> loader treats transform string as eval-able JS / accepts arbitrary HTML
 -> plugin or renderer executes it (or spoofs critical permission UI)
 -> persistent signed/unsigned cache keeps malicious payload
 -> update or locale switch replays the payload
~~~

Break at E: signed index binding + exact digest, schema/version + scope validation, staging and atomic activation, last-known-good rollback, no execute-on-parse. Break A/D: transforms are **registered pure IDs** with typed fields; locale data is plain text and never used for trusted security permission UI. Packs cannot request code execution, network permissions or arbitrary URLs. Offline rollback must never bypass integrity checks.

### Chain E: image/page translation pipeline → XSS or cross-origin data leak

~~~text
External manga page or OCR text -> translator/localization response
 -> translated text treated as rich HTML / untrusted URL
 -> rendered overlay executes script or triggers network fetch
 -> page content/account-related context leaks
~~~

Break D: render overlay as non-executable text and constrained coordinates, not HTML. Break C: only user-approved OCR/translator receives selected cropped page bytes, with privacy controls; use trusted runtime model/engine and version-scoped cache. A translation plugin cannot claim permission to read every source or install a model silently.

### Chain F: worker impersonation → cross-plugin privilege escalation

~~~text
Plugin A forges RPC { pluginKey: "pluginB", method: "kv.get", ... }
 -> broker trusts message-provided actor or generic allow grant
 -> accesses B's data or account profile
 -> changes settings or exports secrets
~~~

Break B: server binds principal to an authenticated, non-reusable worker channel/session and specific installed artifact digest; `pluginKey` in payload is informational only. Namespaces and account snapshot refs are checked against the channel's trusted session, not supplied by the caller. No child worker can grow grants.

## 6. Cross-platform isolation requirements

- **Hosted Linux:** independently sandboxed process (optional hardened container) with no direct network device/host secret mounts, minimal filesystem and IPC only to broker. Use OS primitives (namespace/seccomp/uid) where applicable, with denial tested rather than assumed.
- **Standalone Electron/desktop:** a Node `worker_threads` worker by itself is **not an OS privilege boundary**. Do not give untrusted code `require`/Node integration; use a constrained embedded JS engine/process with only RPC, or a separate OS-sandboxed child with deny-by-default capabilities. Chromium sandbox/isolated renderer may help, but must verify actual OS enforcement.
- **Android/iOS:** evaluate embeddable JS engine isolation and host message interface on each OS. Same-process engines are not equal to OS-level process isolation; app sandbox alone usually protects other apps, **not the app's own credentials from code embedded in the same privileged process**. Require explicit platform threat-model signoff; disable unverified third-party executable plugins on platforms without a credible isolation boundary.
- **Web/PWA:** do not execute untrusted plugin JS in the UI's same-origin JS context; worker/iframe origin+message restrictions, CSP and broker enforcement are required. A Web Worker in the same origin is **not** a substitute for OS isolation from the application's own origin data and permissions.

**Implementation gate:** make this a per-platform threat-model/verification matrix. Do not claim universal sandbox strength based on the existence of a Worker, WebView or JS isolate API.

## 7. Concrete runtime-only policy sketch

~~~ts
// PSEUDOCODE: host-side only. Every handler below is trusted runtime code.
async function brokerDispatch(
  channel: AuthenticatedWorkerChannel,
  rawMessage: unknown
): Promise<RpcResult> {
  const principal = sessions.fromChannel(channel); // NOT rawMessage.pluginKey
  const call = rpcSchema.parse(rawMessage);          // reject unknown fields/size
  const grant = permissions.intersectLiveGrants(principal, call.op);

  if (mandatoryDeny(principal, call, grant)) {
    throw new PluginPermissionError("DENIED");
  }
  const args = validateOperationArguments(call.op, call.args, grant);
  // Canonicalize endpoint/paths/URLs based on trusted grant, not plugin assertions.
  const scoped = await budgets.reserve(principal, call.op, args);
  try {
    permissions.assertStillGranted(principal, grant.revision);
    // The operation handler enforces policies again at actual privileged I/O
    // boundaries (redirect, socket connection, storage transaction).
    return await handlers[call.op].execute({
      principal,
      args,
      grant,
      signal: scoped.signal,
      account: accounts.bindImmutableSnapshot(principal, grant)
    });
  } finally {
    await scoped.release();
  }
}
~~~

**Not security guarantees from this sketch alone:** `AuthenticatedWorkerChannel`, live grant revocation, actual OS isolation, redirect-safe HTTP dialing, and output re-validation need real adapters and tests. A wrapper in a worker cannot enforce any of them.

## 8. Security test gates / negative cases

| Gate | Test | Expected |
|---|---|---|
| RPC identity | forge pluginKey/account ID, replay old worker session | deny; no cross-plugin/account data |
| Method privileges | invoke undeclared operation via manually crafted RPC | deny; no handler execution |
| Permission order | explicit deny plus manifest allow, revoked grant during async request | deny/cancel, never bypass |
| Typed request | odd ports, private IP, rebinding, IPv6, redirect-to-localhost, credential forwarding | deny provider; explicit DAV policy unaffected |
| Request schema | oversized input, unknown fields, injected headers, GET with side-effect path | reject before I/O |
| XSS | malicious title, SVG metadata, translated text, pack string, parser HTML | inert in every view; host bridge unreachable |
| Data pack | tampered digest, stale manifest, bad locale scope, oversized unzip | no activation; trusted previous version preserved |
| Persistence | plugin attempts update of package manifest, source identity, another plugin KV | deny |
| Dynamic fetch | provider signed URL expires; image CDN requires approved Referer | resolve safely; no raw cookie leakage |
| Cross-platform | worker tries actual host file, socket, process and UI access | fail by enforced platform boundary |
| Concurrency | account switch or grant revoke while requests queued/in flight | no cross-account credentials, no stale grant execution |
| Translation | disabled translation, private image and unapproved remote translator | no OCR model/download/upload or network side effect |

Tests must exercise forged IPC directly, not just the happy-path SDK facade, and must verify blocked operations **never reached the underlying host adapter**. A test of `eval` string matching alone is not evidence of sandbox isolation.

## 9. Adoption plan and scope

**P0 first (security-critical, before third-party plugin rollout):**
- Type-only SDK methods, RPC schema and broker with channel-bound principals.
- Policy engine and mandatory deny rules; runtime-owned immutable account snapshots.
- Per-platform sandbox threat matrix and fake-host negative tests.
- Plain-text UI sink contract and zero HTML execution from plugin/pack/translation data.
- PluginProxy vs first-party explicit-private WebDAV authority split.

**P1:** convert one real source (prefer a simpler site) to declarative recipe + JS escape hatch, instrument request-policy parity. Preserve `getUnits` image collection.

**P2:** lazy locale/tag packs and pack updater, with separate signed data authority and rollback.

**P3:** page OCR/translation under opt-in and engine budgets.

No expansion of M1's local-only scope. Security gates are prerequisites for M3 plugin integration. Before adopting, update authoritative 04/05/06/07/08/09/11 and SUMMARY (and 01/02 for new persisted grant records) without creating a second live authority.

## 10. Outstanding decisions to resolve before coding

1. Exact per-platform sandbox engine/process + IPC channel security (including iOS limitations).
2. Whether `endpointRef` can represent signed/image-CDN URL churn without granting unconstrained URL construction.
3. Grant storage, revision, revocation and user approval UI for trusted and third-party plugins.
4. How to propagate user-selected account snapshots into concurrent jobs without leaking secret material into plugin worker.
5. Data-pack signature trust root and whether source-specific packs are signed by the plugin publisher, core maintainer or separately.
6. What HTML-rich source descriptions really need beyond a safe structured text AST.
