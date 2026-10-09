# v2 Account Scope, Passkey and Auth Broker — Adoption Contract

> **Status: implementation design proposal (2026-10-09).** This is an ADR and migration sketch, **not** an implemented contract or replacement for canonical v2 docs 01/02/05/06/07. Read with [14_PLUGIN_RUNTIME_SECURITY.md](14_PLUGIN_RUNTIME_SECURITY.md) and [15_RUNTIME_CREDENTIAL_VAULT.md](15_RUNTIME_CREDENTIAL_VAULT.md). Contradictions below are explicit adoption gates.
>
> **Technical baseline**: The current source_links unique index is (source_platform_id, remote_work_id); the current download_tasks has plugin_key and source_link_id, but no durable account binding; the v2 provider protocol includes provider.login(credentials) and api.fetch(url, RequestInit); and passkeys table lacks revocation and credential-backup metadata. These are *design gaps*, not observed exploitable runtime defects.

## ADR-A: Separate three kinds of identity

1. **Venera identity**: a Hosted Venera user may register several passkeys against *Venera's own RP ID*. A local Standalone profile is not a Hosted WebAuthn user. A passkey credential is not an external website account.
2. **External AccountProfile**: a user-controlled login profile for one website provider or remote mount, with distinct cookie jar and secretRef. Several profiles may exist under one provider. Authentication method is dictated by the external service; passkey-first when supported, otherwise an explicit supported flow.
3. **SourceInstance**: the namespace for remote work IDs. One provider may have (a) a global/public catalog, (b) an account-scoped private library, or (c) a distinct configured remote mount. Account access, source provenance and canonical Content identity are separate concepts.

**Do not equate PluginKey, SourcePlatformId, AccountProfileId, PasskeyCredentialId, SourceInstanceId or ContentId.** Reader position remains ContentUnitId and independent of account selections.

## ADR-B: No login prompts, account mutations or secrets from untrusted plugin RPC

A preliminary SDK sketch in 15 showed PluginAuthFacade.requestLogin/selectProfile/logout. **Replace that proposed shape**: even a host-rendered login popup can be abused by a malicious plugin as a repeated, misleading user prompt. Only trusted UI intent can initiate login/profile switch/logout/passkey registration; it must be tied to an actual recent user gesture or a bounded approved background policy.

~~~ts
// NEW proposed sandbox-facing API. This is the *entire* auth facade.
interface ProviderContext {
  auth: Readonly<{
    status(): Promise<{ state: "guest" | "ready" | "locked" | "expired" }>;
  }>;
  net: Readonly<{
    request(input: {
      endpointRef: string;       // trusted, registered route template
      pathParams?: Record<string,string>;
      query?: Record<string,string>;
      method: "GET" | "POST";    // only if endpoint grant allows
      auth: "none" | "bound";     // cannot select any account ID
      headerProfileRef?: string; // approved non-secret header profile
      responseAs: "html_snapshot" | "json" | "image_resource";
    }): Promise<ProviderResponse>;
  }>;
}

// TRUSTED host UI commands, not serializable/plugin-exposed:
interface TrustedAccountCommands {
  beginLogin(userGesture: TrustedGesture, ownerRef: OwnerRef): Promise<LoginOutcome>;
  chooseAccount(userGesture: TrustedGesture, ownerRef: OwnerRef, accountId: AccountProfileId):
    Promise<ReaderContextRef>;
  logout(userGesture: TrustedGesture, accountId: AccountProfileId): Promise<void>;
  registerVeneraPasskey(userGesture: TrustedGesture): Promise<void>; // Hosted RP only
  revokeVeneraPasskey(userGesture: TrustedGesture, credentialId: string): Promise<void>;
}
~~~

- A Source plugin returning AUTH_REQUIRED does **not** pop a login dialog or pick another account by itself; it produces a typed state that trusted UI may present as a sign-in action.
- Trusted UI creates/chooses ReaderContextRef with selected AccountProfile; IPC channel principal is host-bound. Plugin-provided arbitrary readerContextRef/accountId is never an authorization decision.
- No raw password, WebAuthn assertion challenge handler, raw OAuth token, Cookie, Authorization, raw RequestInit or Vault secret value enters plugin IPC.
- Even the trusted facade is not security enforcement: a forged worker message calling beginLogin/selectProfile/vault.read must be denied by the host's Broker *before* UI/Vault/HTTP effects.
- A plugin can still parse site HTML and gather legitimately fetched user-private content. The broker cannot prove a signed/allowlisted plugin is benevolent; reduce exposed data and restrict allowed request shapes.

## ADR-C: Data model: a scoped instance, not a global account cookie

**Candidate SQLite DDL** (illustrative and not yet a migration; exact naming/authorities must be reconciled against 02_DATABASE_SCHEMA).

~~~sql
-- Local runtime assigns one private immutable owner_scope_id per local profile.
-- Hosted runtime assigns an immutable scope resolvable to tenant/user;
-- the broker MUST verify the authenticated tenant/user; the opaque ID alone is not auth.
CREATE TABLE external_account_profiles (
  id                 TEXT PRIMARY KEY,
  owner_scope_id     TEXT NOT NULL,
  owner_kind         TEXT NOT NULL CHECK (owner_kind IN ('provider','remote_mount')),
  owner_ref          TEXT NOT NULL,
  label              TEXT NOT NULL,
  auth_scheme        TEXT NOT NULL CHECK (auth_scheme IN
    ('cookie_session','basic','api_key','oauth2','site_passkey_session','custom_approved')),
  vault_ref          TEXT, -- opaque OS/host vault reference; NO plaintext secret
  auth_revision      INTEGER NOT NULL DEFAULT 0 CHECK (auth_revision >= 0),
  state              TEXT NOT NULL CHECK (state IN
    ('active','locked','expired','reauth_required','disabled','revoked')),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL
);
CREATE INDEX idx_external_profiles_owner
  ON external_account_profiles(owner_scope_id,owner_kind,owner_ref,state);

-- One source platform may have either global or per-account catalogs.
-- Mount-specific namespaces can be represented by distinct SourcePlatform
-- canonical keys (as separately proposed in 12); don't invent a second
-- mount identity authority here.
CREATE TABLE source_instances (
  id                 TEXT PRIMARY KEY,
  source_platform_id TEXT NOT NULL REFERENCES source_platforms(id),
  account_profile_id TEXT REFERENCES external_account_profiles(id),
  scope_kind         TEXT NOT NULL CHECK (scope_kind IN ('global','account')),
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  CHECK ((scope_kind='global' AND account_profile_id IS NULL)
      OR (scope_kind='account' AND account_profile_id IS NOT NULL))
);
CREATE UNIQUE INDEX ux_source_instance_global
  ON source_instances(source_platform_id) WHERE scope_kind='global';
CREATE UNIQUE INDEX ux_source_instance_account
  ON source_instances(source_platform_id,account_profile_id)
  WHERE scope_kind='account';

-- Proposed source_links migration:
-- add source_instance_id FK source_instances(id), backfill from global instance,
-- require NOT NULL, then replace existing unique (source_platform_id, remote_work_id)
-- with UNIQUE (source_instance_id, remote_work_id). Keep ContentId separate.
-- SourcePlatformId becomes derived via SourceInstance join; avoid keeping a
-- redundant writable SourcePlatformId on SourceLink without equality enforcement.

-- Optional account access evidence, NOT an authorization grant or credential.
CREATE TABLE source_account_access (
  source_link_id   TEXT NOT NULL REFERENCES source_links(id) ON DELETE CASCADE,
  account_id       TEXT NOT NULL REFERENCES external_account_profiles(id),
  state            TEXT NOT NULL CHECK (state IN ('last_seen_allowed','stale','denied')),
  observed_at      TEXT NOT NULL,
  PRIMARY KEY(source_link_id,account_id)
);
-- Application validates both belong to the same Venera user and owner provider.
-- Real access MUST be checked through AuthBroker + upstream status on every fetch.

-- Proposed download_tasks migration:
-- account_profile_id TEXT REFERENCES external_account_profiles(id) ON DELETE RESTRICT;
-- auth_binding_kind TEXT CHECK (auth_binding_kind IN ('none','same_profile'));
-- On resume, reconstruct a NEW immutable per-request snapshot under the SAME
-- profile (not the globally active profile); if missing/revoked pause with typed
-- AUTH_REQUIRED instead of silently adopting a different account.
~~~

**MIGRATION GATES:**
1. Existing public SourceLinks get one global SourceInstance per SourcePlatform before uniqueness changes; preserve ContentId, SectionId, UnitId and current active ReadingSession untouched.
2. Decide for each provider whether remote IDs are globally unique or scoped to one authenticated account. Do **not** infer from URL/title or just assume all private works are separate: reclassifying global↔account requires a controlled review/migration with conflicts surfaced to the user.
3. For a source with globally stable work IDs but account-dependent access, use global SourceInstance **plus** source_account_access evidence, not duplicate canonical Contents. For genuine account-private work IDs, use account-scoped SourceInstance.
4. A SourceLink and account owner must have compatible provider/mount ownership; cross-tenant links fail. Foreign keys alone do not enforce complex ownership relations; host application transaction checks are mandatory, or choose an explicit composite-key schema at adoption.
5. If AccountProfile deletion would orphan account-scoped SourceInstance and SourceLinks, default to disable/revoke and keep canonical provenance/reading history; explicit cleanup must be separate and preserve Canonical IDs.
6. v2 pre-stable schema is allowed to change, but documented v2 cross-file authority must be updated atomically. No undocumented fallback IDs.

## ADR-D: Multi-account execution and long-lived task semantics

**Immutable per-network-attempt auth snapshot**, **durable selected profile ID for jobs**: these are deliberately different lifetimes.

~~~text
User chooses Account A in trusted UI
  -> Create ReaderContext A (opaque host-owned)
  -> Plugin getUnits / AssetResolver
  -> Broker binds channel + trusted context + Account A + auth revision 7
  -> cookie/token injection into approved endpoint inside host
  -> request completes, response is scrubbed and typed
  -> Reader stores unitId as reading position

Parallel:
  Reader Tab 1: A revision 7
  Reader Tab 2: B revision 2
  Download #17: durable Account A identity (same_profile policy)
  user switches default Account A -> B
  Download #17 still uses A, never B

On app restart:
  load Download #17 account_profile_id=A
  -> if A is valid, broker creates NEW request snapshot of A's current revision
  -> if A locked/expired/revoked, job pauses (auth reason) / requests reauth
  -> no implicit fallback to B; no old secret revision serialized in job.
~~~

**Refresh:** broker runs one refresh in flight per (accountId, expectedRevision), stages/validates new credential, CAS updates profile revision; existing requests must either finish under still-valid immutable snapshot (policy-defined) or be cancelled/retried with the **same account only** after a trusted rebind. No raw refresh token passes through JS. A failed refresh doesn't cause cross-account fallback.

**Credential access & HTTP cache:** partition by (ownerScope, ownerKind, ownerRef, accountId, authRevision, approvedOrigin) as appropriate. Even same image URL can be private across accounts. Public bytes can be shared only after a policy proves non-personalized content; deduplication of image hash is not a confidentiality guarantee.

**User preference:** saved default account for each provider is a UI preference, not an authorization source. Per-tab choices take precedence. Where a saved private work is accessible to multiple accounts, the resolver must ask for a trusted selection or use an already valid explicitly bound context; it cannot search other accounts opportunistically.

## ADR-E: Hosted Passkey RP and recovery state machine

WebAuthn Level 3 Recommendation (2026-08-25) defines passkey/public-key mechanisms and optional PRF. Implementation libraries must enforce real WebAuthn verification; never hand-roll signature parsing, COSE verification, origin rules or attestation.

~~~text
HOSTED SIGN-UP:
  trusted Venera UI -> server creates random single-use challenge
  -> browser/platform authenticator registers for Venera-owned RP ID
  -> server verifies type, challenge, exact allowed origin, RP ID hash,
     user presence, required user verification, credential public key
  -> store public-key credential, user ID, backup metadata (if available)
  -> mark challenge consumed transactionally
  -> prompt user to register backup passkey / strong recovery

HOSTED SIGN-IN:
  challenge generated server-side, bound to RP/session/purpose + short expiry
  -> credential assertion from browser/OS
  -> server verifies challenge, origin, RP ID, signature, user-binding, UV
  -> consume challenge exactly once and record credential last use
  -> issue runtime's existing opaque selector+HMAC session token
  -> optional re-auth/step-up for adding/removing credentials or export

SITE SIGN-IN:
  external website RP's actual flow; Venera cannot invent passkeys for it
  -> supported browser/OAuth handoff or site-owned cookie-login flow
  -> host stores supported session material in external AccountProfile Vault
  -> provider plugin receives only readiness/approved site data
~~~

**Proposed passkey-specific persisted additions**:
- To existing passkeys: revoked_at, user-defined safe label, transports metadata, backed_up/backup_eligible indicator where returned, last_used_at; name the actual verification library output and treat AAGUID/sign-count/backup metadata as advisory when absent.
- New webauthn_challenges table: id/opaque nonce, *hash* of high-entropy challenge, purpose (register/authenticate/step_up), expected RP ID/origin policy reference, bound initial session/user when applicable, created/expiry and consumed_at. Atomic single-use consume, TTL cleanup. Rate limit challenge creation and failed verification.
- Recovery: pick a **policy** before implementing. Recommended Hosted personal-mode default: at least two registered passkeys (one spare). Optional user-generated high-entropy offline recovery codes may be offered but **must be labeled a weaker bearer recovery channel** and strongly controlled; a strict passkey-only mode should not silently enable them.
- Device-bound vs synchronized credentials: allow both where policy permits. A signature counter may be unreliable for synced credentials; don't hard-fail solely because it didn't increase. Do not assume backup-state metadata is present or definitive.
- RP constraints: HTTPS and exact configured relying-party origin. Moving a self-hosted instance to a new RP ID requires fresh registration or a designed recovery/migration path. Third-party JS may not specify RP ID or origin allowlists.

**PRF/Vault:** optional WebAuthn PRF may be used as one wrapper for a randomly generated Vault DEK after platform-capability testing; it is **per-credential** and requires user interaction. A plain WebAuthn assertion signature cannot be used as an encryption key; deleting the only PRF-wrapping credential without verified alternate wrapper risks permanent credential vault loss. OS Keychain/Keystore remains default local vault key protection.

## ADR-F: Multi-account trusted UX (not part of Plugin capability)

~~~text
Source page
  Account: [Personal ▾]  [Connect another]
  Logged in: Personal
  Reader tab binds: Personal
  Download binds: Personal

On "Connect another":
  Host-owned form/browser opens
  Host collects login, selects secret storage and auth profile
  Host verifies account identity where possible, asks user to confirm
  On success profile becomes available in trusted chooser
  Plugin receives no field values, tokens or new generic privileges

On click account switch:
  Host revalidates requested AccountProfile belongs to same user+provider
  Browser/reader binds new opaque context
  Current page fetched again under selected account where needed
  ReadingSession(unitId) stays unchanged

On account deletion:
  Host cancels or pauses affected tasks, revokes profile and vault secret
  Canonical library records and reader positions remain unless user
  explicitly chooses their deletion in a separate action
~~~

Account UI should show *method and session status* without disclosing secrets. Browser login may not hand system-browser cookies back to app automatically; a native passkey RP or OAuth token handoff is not the same as a generic authenticated gallery session.

## ADR-G: Testable negative cases and acceptance criteria

| Input/action | Expected |
|---|---|
| Forged plugin request to beginLogin/logout/selectProfile without trusted gesture | DENY, trusted UI untouched |
| Plugin sends forged accountId / vaultRef in RPC | DENY before vault/HTTP adapters are invoked |
| Account A and B same provider, concurrent readers | CookieJar and cache isolated; no wrong-account request |
| Account A expires while B active | A asks reauth/pauses; B unaffected; no fallback to B |
| Restart A-bound download after switch to B | Rebind fresh snapshot to **A** or pause; never B |
| Provider global work ID under A and B | One global canonical SourceLink, separate access evidence |
| Provider account-private remoteWorkId collision | Two distinct SourceInstances; no collision or silent content merge |
| Passkey registration with invalid origin, RP, challenge, missing UV | Rejected, never creates credential |
| Replayed WebAuthn challenge or revoked credential | Rejected, no Venera session |
| Register second passkey, revoke first | Same user remains able to log in via second |
| PRF unavailable/only wrapper removed | No silent vault loss; require alternate verified wrapper/recovery |
| Third-party external RP lacks passkey support | UI presents only supported auth; no false "passkey conversion" |
| HTML/translation/plugin JS tries to read user-entered login fields | UI isolation and RPC enforcement keep secret inaccessible |
| Account picker selects profile in another hosted tenant | Host denies before any secret access |
| Same-profile refresh while requests in flight | CAS consistency and no cross-account cookie injection |

Every test must send at least one *forged protocol message*, not just use friendly SDK calls. For security tests, assert the privileged adapter **was never called**, not merely that an error was returned.

## Adoption order / existing canonical files

1. **M3.0 contract review:** decide SourceInstance identity granularity and browser-site passkey feasibility; confirm platform-specific worker isolation and vault adapters.
2. **05_PLUGIN_SYSTEM.md:** retire provider.login(credentials)/getRequestHeaders/raw api.fetch target contracts; make login/profile mutation host UI-only; define account-agnostic plugin RPC status and endpoint-based approved requests.
3. **01_ENTITIES.md + 02_DATABASE_SCHEMA.md:** introduce one ExternalAccountProfile model, SourceInstance, optional access evidence; migrate SourceLink unique index and download task bound profile; add Hosted passkey/challenge lifecycle. Never duplicate an existing account schema.
4. **07_FEATURES.md:** revise DownloadTask to persist selected profile identity and reacquire per-request revision on restart; existing UC-REMOTE-001/ContentUnit reader identity remains authority.
5. **04/06/09:** broker+vault ports, secret-safe account events, per-platform isolation/encryption profiles and privacy policy.
6. **11_MILESTONES.md + SUMMARY.md:** M1 local-only; M3.0 identity/auth tests; hosted Venera passkey UI belongs with Hosted auth M4, not a prerequisite for local M1.
7. **Implement a single reference provider** with two test accounts and mocked site/redirect/session flows before migrating all venera-configs plugins.

### Open decisions requiring an explicit ADR before code

- SourceInstance namespace assignment: which providers have globally stable IDs vs account-specific IDs, and user-driven remapping UI.
- User vs tenant owner scope representation: standalone needs a local trusted principal and hosted needs auth_users + tenant validation.
- First-party WebDAV mounts vs provider account profiles: avoid two separate credential-vault authorities for the same instance.
- Backend account verification for cookie-only gallery sites where a trustworthy account identity endpoint is unavailable.
- Which external website passkey flows work in a host-owned browser context per target OS; whether a system-browser login can hand back a site session.
- Hosted strict passkey-only policy vs high-entropy recovery codes and user support burden.
- Vault backup and key rewrap, if optional WebAuthn PRF is enabled.

### References

- [WebAuthn Level 3 Recommendation (2026-08-25)](https://www.w3.org/TR/2026/REC-webauthn-3-20260825/)
- [W3C WebAuthn PRF explainer](https://github.com/w3c/webauthn/blob/main/explainers/prf-extension.md)
- [Apple: Supporting passkeys](https://developer.apple.com/documentation/authenticationservices/supporting-passkeys)
- [Apple: Passkeys in browser applications](https://developer.apple.com/documentation/authenticationservices/passkey-use-in-web-browsers)
- [Android: Credential Manager WebView](https://developer.android.com/identity/sign-in/credential-manager-webview)
- [OWASP Authentication](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)
