# v2 Website Authentication Broker & Credential Vault

> Status: **PROPOSAL**, 2026-10-09. Companion to [12_REMOTE_READING_ACCESS.md](12_REMOTE_READING_ACCESS.md), [13_PLUGIN_DATA_LOCALES_TRANSLATION.md](13_PLUGIN_DATA_LOCALES_TRANSLATION.md), and [14_PLUGIN_RUNTIME_SECURITY.md](14_PLUGIN_RUNTIME_SECURITY.md). Not an implemented API and not yet the canonical 00–11 design authority.
>
> Project finding: existing 05_PLUGIN_SYSTEM.md target interfaces include provider.login(credentials: unknown), login(credentials: Record<string,string>), getRequestHeaders(), and api.fetch(url, RequestInit). The older docs/plans/source-runtime-account-request-policy.md already sketches runtime-owned cookies/accounts/immutable snapshots. This document closes the **vault, website-auth and broker-interface** contract gap rather than asserting that deployed code is exploitable.

## Decision

**JS plugin declares site-specific auth methods and parses approved non-secret responses, but never receives passwords, reusable session cookies, API keys, OAuth refresh tokens or any ability to decrypt them.** The host/runtime owns the trusted login UI, AuthBroker, CredentialVault, isolated cookie jars, refresh, request-time credential injection, revocation and network egress policy. Plugin SDK is typed RPC, not raw host JS interfaces.

Reference password-manager threat models (1Password, Bitwarden) for key isolation, encrypted-at-rest vaults, lifecycle and access control; **do not reimplement a cloud password manager, invent crypto, or claim zero-knowledge**. The local/hosted trusted runtime must use a website credential to make authenticated requests. Password-manager zero-knowledge sync does not transfer automatically.

**Important distinction:** Venera-issued hosted API tokens can be verified by selector + HMAC hash (06_SECURITY_AUTH_RECOMMENDATION); third-party website credentials must be retrievable or useable to authenticate to the upstream site. One-way hashing those website passwords/cookies would be incorrect.

## 1. Trust boundaries and protected information

~~~text
Trusted Runtime-owned Login UI / system browser
  -> AuthBroker [login, refresh, request snapshot, logout]
       -> CredentialVaultPort [save/use/rotate/revoke]
            -> OS platform secret backend (key or small secret)
            -> encrypted per-account cookie/token records
       -> first-party AuthenticatedHttpClient
            -> approved origin/method/request schema
            -> CookieJar partition + credential injection
            -> actual TLS request; redirect/SSRF checks
  -> bounded non-secret result/status through typed RPC
  -> Isolated JS source plugin: search/detail/sections/getUnits/parser
~~~

- **Protected secrets**: website password (if explicitly remembered), Basic/Digest credentials, API keys, HTTP cookie values, authorization headers, OAuth access/refresh tokens, signing secret and opaque bearer tokens.
- **Sensitive metadata**: usernames, selected profile name, login origin, account identity and visit history. Do not expose unnecessary metadata in telemetry or logs.
- **Sources of untrusted data**: website HTML/JSON, login-origin hints from JS, Redirect/Set-Cookie handling, source-specific JSON config, credential-profile IDs sent by plugin, plugin source and translation packs.
- **Authentication principal**: resolved by the host from worker IPC channel plus installation identity, local user/hosted tenant, signed artifact identity and live grants. A plugin-supplied ownerId/pluginKey/vaultRef is never authorization.

## 2. Proposed persisted model (logical, not DDL)

~~~text
CredentialProfile (canonical non-secret record)
  id                    UUID, immutable
  userScope             local owner ID / hosted tenant and user ID
  ownerKind             provider | remote_mount
  ownerRef              provider identity or RemoteMount UUID
  authKind              cookie_session | basic | api_key | oauth2 | approved_custom
  label                 user-assigned display label
  approvedOriginRefs    host-managed references to origin grants
  credentialVersion     monotonic revision
  state                 active | locked | expired | reauth_required | revoked
  vaultEntryRef         opaque reference, never a plain token or path
  lastValidatedAt       optional
  expiresAt             optional
  createdAt, updatedAt

VaultRecord (protected, separate from account metadata)
  id                    opaque ID
  boundProfileId        UUID
  type                  password | cookie_jar | access_token | refresh_token |
                        api_key | signing_secret
  wrappedKeyRef          OS-backed wrapping-key reference
  keyVersion            integer
  ciphertext            authenticated encrypted bytes
  encryptionMetadata    algorithm, nonce, AAD version
  createdAt, updatedAt

CookieJarPartition (logical)
  userScope + ownerKind + ownerRef + profileId + partitionId
  RFC-compliant per-cookie host/domain/path/secure/HttpOnly/SameSite/expiry
  encrypted-at-rest cookie values, not one global host cookie jar

RequestCredentialContext (EPHEMERAL trusted runtime only)
  principal             channel-bound runtime principal
  profileId             bound when request created
  credentialVersion     immutable for queued request/retry
  permissionRevision    checked again at privileged I/O
  endpointRef           registered host-approved origin + route + operation
  lifetime              bounded per request
~~~

No secret fields in normal SQLite domain tables, configJson, plugin KV, source JavaScript bundle, JSON pack, page cache, local diagnostics or hosted logs. If user/profile labels need privacy at rest, encrypt them too.

Use **authenticated encryption**, for example AES-256-GCM through a well-reviewed cryptography library. Bind tenant/user/owner/profile/type/key-version as authenticated AAD. Use strong random per-operation nonces, key versioning, and correct atomic storage lifecycle. AEAD alone does not prevent replay of *old but valid ciphertext*; if rollback is in threat scope, maintain monotonic authenticated version evidence independently of attacker-controlled blob storage.

**Pragmatic storage split:** a few passwords/tokens may live directly in the OS credential store, with opaque secretRef persisted in SQLite. Large per-profile cookie jars may be encrypted into app-private blob storage with a data-encryption key (DEK) protected by an OS-backed key-encryption key (KEK). Keep encryption keys outside the database and outside plugins. Do not promise extra security solely from using envelope encryption.

## 3. OS secret backend matrix and fail-closed behavior

| Environment | Recommended adapter | Caveat |
|---|---|---|
| iOS/macOS | Keychain with least-permissive accessibility and optional device-auth gate | ThisDeviceOnly items do not migrate across devices; foreground-only unlock can block background prefetch. App code with permitted Keychain access remains powerful |
| Android | Android Keystore for non-exportable keys + encrypted app-private credential records | TEE/StrongBox support is device dependent; compromised host process can still request permitted cryptographic operations |
| Windows | DPAPI in **current-user** scope or supported Credential Manager service | DPAPI same-user processes may have access; don't use broad machine scope for personal credentials |
| Linux desktop | Secret Service, GNOME Keyring/libsecret, KWallet or supported portal | Electron safeStorage basic_text is insecure fallback; fail closed if no real backend |
| Docker, NAS, VPS, Hosted | external Vault/KMS/Secrets Manager and service identity, per-tenant data access control | never assume local desktop keychain exists in a headless container. Server-side decryption is not zero-knowledge. Avoid raw secrets in argv or logs |

Backend probe is a **startup / unlock gate**. If no secure persistent store, return VAULT_BACKEND_UNAVAILABLE and offer strictly session-only in-memory auth, or ask for a configured supported backend. Never silently persist plaintext to file or weakly encrypt it under a hardcoded/static key.

Device-only key loss, OS reinstall, app re-signing or OS credential reset can make stored credentials unrecoverable; show REAUTH_REQUIRED and keep canonical reading history. For optional portable backup, separately design user-opt-in portable authenticated encryption and KDF (e.g., Argon2id); no default plaintext cookie export and no implicit credential sync across devices or to hosted server.

User-presence/biometric gate should protect sensitive account changes/export and optional unlock, **not every comic image request**. Background download when device is locked may be unsupported by stricter key accessibility; surface that tradeoff, do not bypass it.

## 4. Authentication modes and ownership

| Method | User interaction and runtime handling | JS plugin sees |
|---|---|---|
| Public/guest | No auth | Normal site data |
| Username/password website login | Trusted native runtime form; remember-password is optional; broker posts approved login request | auth state, safe result, *not* input/password |
| Cookie-based website browser login | Isolated runtime-owned browser context if required; capture approved session material through trusted broker | auth status, *not* cookie jar |
| WebDAV HTTP Basic/Digest | Trusted mount credential UI and first-party network transport | Nothing; website plugins cannot borrow mount secrets |
| API Key | Trusted secret input; broker injects into approved origin/operation only | status and bounded response |
| OAuth2/OIDC | **system browser / external user agent** + Authorization Code with PKCE; host validates callback state and handles token exchange | status and permitted capability summary |
| MFA / challenge | User completes trusted interactive flow; OTP/TOTP seed not stored by default | safe success/failure |

For OAuth native clients follow [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252): external browser, no embedded OAuth WebView, PKCE. For **non-OAuth legacy website logins**, if embedded browser is unavoidable, use a trusted isolated per-account profile, block plugin JS injection and app bridge, constrain origins, and test platform cookie isolation; do not equate it with secure system-browser OAuth.

Plugin metadata can declare label keys and field types, **never arbitrary login HTML or event handlers**. Custom source authentication may be impossible without unsafe JS access: prefer explicit manual login/session import under trusted UI, a first-party audited adapter, or return UNSUPPORTED_AUTH rather than handing the password to the plugin.

## 5. Proposed SDK facade: no raw credential return

~~~ts
// Exposed inside sandbox worker as typed RPC facade only.
interface PluginAuthFacade {
  status(): Promise<{
    state: "guest" | "active" | "locked" | "expired" | "reauth_required";
    profileRef?: string;   // opaque and bound to the calling plugin
    label?: string;        // non-secret host-approved summary
  }>;
  requestLogin(opts?: { scheme?: "cookie_session" | "basic" | "api_key" | "oauth2" }):
    Promise<{ state: "active" | "cancelled" | "reauth_required" }>;
  selectProfile(profileRef: string): Promise<void>;
  logout(profileRef: string): Promise<void>;
}

interface PluginAuthAwareNetworkRequest {
  endpointRef: string;                 // registered approved endpoint, not arbitrary URL
  method: "GET" | "POST";               // further constrained by endpoint grant
  pathParams?: Record<string, string>;
  query?: Record<string, string>;
  headerProfileRef?: string;           // identifies approved profile, not raw header
  auth: "none" | "active_profile";
  responseAs: "html_snapshot" | "json" | "bytes";
}

// HOST-ONLY contract. SecureSecretHandle is not serializable to plugin IPC.
interface CredentialVaultPort {
  store(profile: TrustedProfile, kind: SecretKind, input: SecureSecretInput):
    Promise<VaultRecordRef>;
  withCredential<T>(
    principal: TrustedPrincipal,
    operation: ApprovedOperation,
    secretRef: VaultRecordRef,
    fn: (handle: HostOnlySecretHandle) => Promise<T>
  ): Promise<T>;  // MUST not allow returning a raw secret as T
  rotate(profile: TrustedProfile, expectedRevision: number, input: SecureSecretInput):
    Promise<number>;
  revoke(profile: TrustedProfile): Promise<void>;
}
~~~

**Never expose** getPassword(), getCookies(), getToken(), decryptSecret(), raw CookieJar, Set-Cookie, API key in RequestInit, token-bearing URLs, unrestricted headers or a privileged browser DOM to JS plugins. A plugin-config login form with custom HTML/event JS is also prohibited. Host must enforce typed runtime RPC and schema; TS types alone are not a security boundary.

Note: a generic callback typed as T could accidentally return the secret; the actual trusted implementation should restrict output to safe result schema and avoid any free-form “decrypt and return” method, including exceptions and logs.

## 6. Request-bound credential lifecycle

~~~text
CONNECT:
 trusted UI obtains inputs -> AuthBroker validates origin/operation
 -> approved login (host network) -> captures Set-Cookie/token privately
 -> Vault save/encrypt -> CAS activate Profile revision 1

OPEN PAGE / DOWNLOAD:
 sandbox asks ctx.net.request(endpointRef, auth=active_profile)
 -> broker identifies worker principal and permitted profile
 -> bind immutable (profileId, credentialRevision, grantsRevision)
 -> validate route, host, method, body, redirect, public/private policy
 -> vault uses/retrieves approved credential in trusted host only
 -> host applies RFC-compliant Cookie/Header matching to correct origin
 -> perform TLS request and bounded response classification
 -> sanitize/strip Set-Cookie, Authorization, token data
 -> return approved site data or typed failure to sandbox

401 / EXPIRY:
 -> refresh/re-login policy, singleflight per profile
 -> stage new secret, check using approved validation route
 -> atomically replace vault ref and increment profile revision (CAS)
 -> queued/retried calls under old revision fail or trusted broker rebinds
    the SAME profile explicitly; never switch to active account B

LOGOUT / DELETE / REVOKE:
 -> revoke grants and cancel queued/in-flight calls
 -> delete local secret + cookie partition, invalidate authenticated cache
 -> attempt upstream logout/revoke when supported
 -> preserve unrelated profiles, local comic content and reading positions
~~~

Important: WebView and external-browser cookie flows may not produce identical credentials and the app must not claim ability to extract an OAuth browser's global cookies. OAuth uses its callback/token flow. Cookie session login requires approved, platform-specific host-owned capture and partitioning.

Do not store reusable secrets in authenticated HTTP response caches or redirect logs. HTTP response may contain token fields: sensitive auth responses are classified and captured in host-controlled auth handlers, not returned wholesale as arbitrary plugin JSON. Site data naturally reveals some user-specific metadata to parser plugins; minimize and namespace outputs.

## 7. Cookie partitioning and origin trust

Cookie storage authority: (user/tenant, plugin or mount owner, profileId, browser partition, cookie domain/path). Implement HTTP cookie matching (host-only/domain, Path, Secure, HttpOnly, SameSite, expiration, public suffix rules). The runtime adds additional site/operation grants even if a cookie itself matches a domain. Do **not** automatically share all eTLD+1 cookies across plugins or every CDN subdomain.

- Plugin A must not read Plugin B's profile or WebDAV mount credentials, even if they authenticate to the same hostname.
- Referer-required CDN is not a reason to send login cookies to a CDN origin.
- Cross-origin redirects drop Authorization/Cookie unless an independently approved scoped flow says otherwise, with exact destination policy checks and DNS pinning.
- E-Hentai/ExHentai use separate registrable domains; if both required, grant and store distinct scoped origins explicitly, not broad wildcard cookie leakage.
- Cookies flagged HttpOnly are hidden from page JavaScript, **not automatically hidden from privileged host network code**. Enforce plugin isolation independently.
- Authenticated page/image cache keys must include profile identity and credential revision; never leak personalized response into another profile's cache.

## 8. Attack chains (threat model, not verified exploitable code)

**A. Source config -> login form injection -> password theft.**
~~~text
Malicious plugin supplies HTML login form / oninput hook
 -> runtime executes untrusted form
 -> plugin captures typed website password
 -> outgoing image/API request leaks secret
~~~
Break: trusted schema-rendered UI, no arbitrary HTML/JS form, no secret-bearing login RPC.

**B. Worker impersonation -> cross-plugin credential theft.**
~~~text
Plugin A forges {ownerRef: Plugin B, vaultRef: ...}
 -> host trusts caller-supplied identity
 -> B's cookie/token injected into A's request
~~~
Break: channel-bound identity, user/tenant/profile ownership, operation and origin checks on *every use*.

**C. Authenticated image redirect -> credential forwarding / SSRF.**
~~~text
Allowed image URL redirects to attacker or private LAN
 -> raw network client forwards Cookie/Authorization
 -> credentials or private service data leak
~~~
Break: manual redirects, credential stripping, validated origins/IPs, separate scoped trusted WebDAV network capability.

**D. Disk backup -> lost OS encryption isolation.**
~~~text
Attacker copies venera.db and cookie files
 -> key also stored beside files or weak Linux basic_text fallback
 -> decrypts/replays cookies
~~~
Break: OS/hardware protected keys, ciphertext only, backend fail closed, no portable plaintext backups.

**E. Account-switch race.**
~~~text
Request queued using A -> user switches to B -> retry uses active B cookies
 -> cross-account disclosure and contaminated shared image cache
~~~
Break: immutable request snapshot, per-profile CAS rotation, revision check, cache partition and cancellable requests.

**F. Hosted tenant vaultRef IDOR.**
~~~text
Tenant X guesses/obtains Y's vaultRef
 -> hosted broker decrypts because ID looks valid
 -> sends network request authenticated as Y
~~~
Break: owner/tenant/principal grant checked for every vault use, per-tenant protected storage and audited policy deny.

## 9. Acceptance and migration gates

Tests must bypass friendly SDK API and send forged RPC directly, proving denied operations never hit real Vault/HTTP adapters:

1. Secret exfil attempts through plugin.login, raw RequestInit/headers, cookie reads, KV and forged vaultRef all denied.
2. Linux no keyring / Electron basic_text => VAULT_BACKEND_UNAVAILABLE or strict session-only, no persisted plaintext.
3. Mac/iOS device-locked Keychain and Android key unavailable/StrongBox fallback are reported correctly; no misleading hardware-backed claim.
4. Encrypted record integrity/AAD swap, key-version mismatch and partial rotation fail closed without corrupting other profiles.
5. Request queued for account A never executes with B; refresh in-flight is singleflight and CAS-safe; revocation kills stale queued work.
6. Malicious auth-site redirect, image CDN, signed URL, public suffix/cookie path and cross-origin Authorization leak all blocked.
7. OAuth state/PKCE/callback validation; no embedded OAuth WebView or app-wide browser-cookie extraction.
8. Login UI malicious plugin labels are inert; no plugin-provided HTML or event-hook reads password entry.
9. Hosted tenant X cannot access Y's secret or mount; verified with guessed and replayed vault IDs.
10. Logout deletes partitioned session and queued grants without erasing canonical reading history.
11. Secret backup default excludes all vault entries; explicit export requires separate consent/crypto design.

**Implementation order:** P0 data/port/security boundary and platform adapter feasibility -> P1 one first-party/bundled secure provider login -> P2 migrate repeated venera-configs account/cookie/request code with compatibility tests -> P3 hosted tenant KMS and portable encrypted backups (optional). This is a precondition for M3 online third-party plugins, **not an expansion of M1 local-only MVP**.

On adoption consolidate into the existing authoritative 01/02/04/05/06/09/11/SUMMARY and design the exact device backend + hosted KMS. Avoid parallel live schema authorities.

## Primary references

- [Apple Keychain accessibility](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Microsoft DPAPI CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
- [Electron safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [OWASP Cryptographic Storage](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)
- [RFC 8252 native OAuth](https://www.rfc-editor.org/rfc/rfc8252)
- [MDN secure cookies](https://developer.mozilla.org/en-US/docs/Web/Security/Practical_implementation_guides/Cookies)
- [1Password encryption design](https://support.1password.com/authentication-encryption/)
- [Bitwarden encryption](https://bitwarden.com/help/what-encryption-is-used/)

**Unresolved choices**: actual Flutter/JS/Electron host Keychain/Keystore bridges; cross-platform non-OAuth login browser partition/capture; background unlock policy; optional external password-manager Autofill; hosted tenant key isolation and recovery; site-specific auth signatures without giving hooks raw secrets. Do not claim those are solved by merely defining CredentialVaultPort.
