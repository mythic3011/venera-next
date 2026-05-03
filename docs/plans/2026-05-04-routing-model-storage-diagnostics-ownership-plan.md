# 2026-05-04 Routing, Model, Storage, Diagnostics Ownership Plan

## Goal
Turn the ownership lessons from `docs/tech-notes/routing-model-storage-diagnostics-ownership.md` into a staged, low-risk implementation plan that reduces truth-boundary ambiguity without mixing in unrelated feature work.

## Scope
- Routing ownership for reader-critical flows.
- Model/class ownership boundaries across `pages/`, `features/`, `foundation/`, `utils/`.
- Storage authority declaration and ambiguous-read control.
- Legacy log vs structured diagnostics drift reduction.

## Out Of Scope
- Full router rewrite.
- Broad feature refactors unrelated to ownership boundaries.
- Behavior-changing migrations during inventory phases.
- Mixing appdata startup residue cleanup into reader-routing migration lane.

## Guiding Rules
- Authority before patch.
- Inventory first, migration second.
- One domain, one declared authority.
- Critical reader/session routes must not remain `observerAttached=unknown`.
- No behavior change in inventory tasks.

## Phase 1: Inventories (No Behavior Change)

### R-routing-inventory-1
- Enumerate all route construction callsites:
  - `context.to(...)`
  - `Navigator.push*` / `popAndPush*` / `pushReplacement*`
  - `AppPageRoute(...)`
- Map reader/detail/history/source entrypoints.
- Classify route host:
  - main observed navigator
  - nested navigator
  - dialog/overlay
- Record observer coverage status and unknown ownership gaps.

Deliverable:
- `docs/plans/2026-05-04-routing-inventory-ownership-table.md`

Acceptance:
- Every reader-related route callsite is listed with navigator role and observer coverage label.
- Unknown nested flows are explicitly tracked as backlog items.

### M-model-inventory-1
- List classes declared in `lib/pages/**` and `lib/utils/**`.
- Find cross-feature imports from `pages/**`.
- Map duplicate concept shapes:
  - reader request contract
  - comic detail VM/state models
  - reading progress models
  - source package/install metadata
  - local import metadata
- Assign owner module per concept (`feature/domain`, `feature/data`, `feature/presentation`, `foundation`, page-local only).

Deliverable:
- `docs/plans/2026-05-04-model-ownership-inventory.md`

Acceptance:
- Each duplicate concept has one named owning module.
- Page-local classes imported by other modules are flagged for migration.

### ST-storage-authority-inventory-1
- Build domain authority table:
  - Domain
  - Canonical authority
  - Allowed fallback
  - Cache/preference/diagnostic-only reads
  - Forbidden/ambiguous read-write paths
  - Migration status
- Cover at least:
  - local library
  - reader progress/session
  - source repositories
  - UI preferences
  - legacy compatibility surfaces

Deliverable:
- `docs/plans/2026-05-04-storage-authority-table.md`

Acceptance:
- Every user-visible domain has one canonical authority.
- Ambiguous authority reads are listed with owner and removal path.

### L-log-unify-1
- Inventory legacy `Log.*` writes vs structured diagnostics writes.
- Tag each event as:
  - UI notification only
  - runtime diagnostic
  - both (requires correlation bridge)
- Define required runtime fields baseline:
  - identity
  - authority
  - lifecycle phase
  - correlationId
  - entrypoint/caller (when relevant)

Deliverable:
- `docs/plans/2026-05-04-log-unification-inventory.md`

Acceptance:
- Runtime-critical events missing structured fields are explicitly listed.
- Adapter strategy is documented with no behavior change yet.

## Phase 2: Narrow Centralization Migrations

### R-reader-route-facade-1
- Introduce/complete `AppRouter.openReader(...)` as the sole reader-open route authority.
- Centralize in one place:
  - route factory/label
  - navigator target selection
  - route diagnostics metadata
  - lifecycle correlation identity seed
- Convert reader entrypoints to facade usage only.

Acceptance:
- Reader opens no longer construct ad-hoc route payloads in pages.
- `NaviObserver` correlation is stable for main-navigator reader flows.

### M-model-1 / M-model-2 / M-model-3
- `M-model-1`: ensure `ReaderOpenRequest` has a stable reader-owned import path.
- `M-model-2`: move comic detail VM/state models under `features/comic_detail/...` boundaries.
- `M-model-3`: move source package/install metadata ownership into `features/sources/comic_source/...`; source pages render controller state only.

Acceptance:
- Cross-feature imports do not depend on page-local model definitions.
- Duplicate concept shapes are reduced to one authority contract each.

### ST-storage-1
- Introduce authority table as code-level contract docs/reference.
- Convert ambiguous reads into explicit helpers labeled `authority`, `fallback`, or `cache/preference`.
- Disallow new direct legacy reads outside migration boundary.

Acceptance:
- New storage reads include authority-role labeling by design.
- Reader/storage routes no longer rely on implicit multi-store authority.

### L-log-unify-2
- Implement thin compatibility bridge direction:
  - one runtime event -> structured diagnostic record
  - optional legacy display as projection
- Ensure runtime-critical logs carry required identity/authority/lifecycle/correlation fields.

Acceptance:
- Critical diagnostic events are queryable and correlation-ready from one structured source.
- Legacy and structured streams do not diverge on event meaning.

## Phase 3: Backlog and Hardening

### R-routing-inventory-2
- Classify known unknown nested navigator flows (including existing `PageRouteBuilder` unknown owners).
- Add `navigatorRole` labels for known nested flows.
- Keep behavior unchanged unless approved follow-up migration is planned.

### A-appdata-cleanup-1 (Separate lane)
- Remove comic source startup rewrite residue in init path.
- Keep this lane separate from routing/model/storage migrations.

## Execution Order
1. Phase 1 inventories (`R`, `M`, `ST`, `L`) and publish docs.
2. Review and freeze ownership decisions.
3. Phase 2 narrow migrations in small slices:
   - `R-reader-route-facade-1`
   - `M-model-*`
   - `ST-storage-1`
   - `L-log-unify-2`
4. Phase 3 backlog/hardening lanes.

## Verification Gates Per Slice
- `dart analyze`
- Targeted tests for touched modules (reader routing, source management, storage authority helpers, diagnostics pipeline).
- For route slices, verify route-correlation diagnostics contain matching route identity on push/pop for main observed navigator paths.

## Risks
- Route coverage assumptions for nested navigators may hide owner gaps.
- Model moves can create import churn if done in broad batches.
- Storage authority labeling may reveal hidden legacy dependencies.
- Log unification can add noise if field contracts are not enforced.

## Mitigations
- Keep migrations slice-sized and feature-scoped.
- Require inventory evidence before each migration PR.
- Enforce explicit authority-role tagging for new storage reads.
- Apply required diagnostic field checks for runtime-critical events.

## Done Criteria
- Reader route opening is centralized and correlation-stable.
- Ownership inventories exist and map to concrete migration tasks.
- Storage authority table is active and referenced by new code paths.
- Runtime-critical logs are structured-first with aligned legacy projection.
