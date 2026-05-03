# Tech Note: Routing, Model, Storage, and Diagnostics Ownership Lessons

## Problem

The reader debugging work exposed a broader architectural pattern.

The issue was not only a reader bug. It was a repeated ownership problem across
routing, model placement, storage authority, and diagnostics.

Each area works locally, but ownership is distributed. That makes debugging
costly because each module can explain only part of the truth.

## 1. Routing Ownership Is Scattered

The current app does not have a clean centralized routing module for critical
flows.

Reader navigation is built through scattered helpers, `BuildContext.to()`,
`AppPageRoute`, local page actions, and observer-side diagnostics. Each part
owns only part of the truth.

Because of this, a reader screen can be created and disposed while the main
`NaviObserver` does not clearly show the same route lifecycle.

Observed symptom:

```text
ReaderWithLoading routeHash = 297005604
navigator.didPush routeHash = 988811969 ComicDetailPage
navigator.didPop  routeHash = 988811969 ComicDetailPage
```

This means the reader route lifecycle cannot be reliably correlated with the
global navigator trace.

## Route Observer Coverage Finding

Current diagnostics can now distinguish main observed routes from nested
navigator routes.

Observed correlated case:

```text
navigatorHash == mainNavigatorHash
observerAttached == true
navigator.lifecycle.didPush.routeHash == navigator.push.host.routeHash
```

This means the route is pushed through the main observed navigator and can be
correlated with `NaviObserver`.

Nested / unknown case:

```text
nestedNavigator == true
observerAttached == unknown
navigatorHash != mainNavigatorHash
```

This does not imply a bug by itself. It means the route belongs to a nested
navigator whose observer coverage is not yet classified.

Policy:

- Reader routes must go through `AppRouter.openReader()` and the main observed
  navigator.
- Nested navigators are allowed for local flows, tabs, dialogs, and inner
  journeys.
- Any route that affects reader/session lifecycle must not stay in
  `observerAttached=unknown`.

Backlog:

```text
R-routing-inventory-2
- classify nested navigator owner for routeHash=140732557 (PageRouteBuilder)
- add navigatorRole labels for known nested flows
- no behavior change
```

### What We Learned

#### Routing must have one authority

A critical screen should not be opened by many UI components constructing
routes directly.

Bad pattern:

```text
comic detail -> context.to(AppPageRoute(...Reader...))
history -> context.to(AppPageRoute(...Reader...))
local favorites -> context.to(AppPageRoute(...Reader...))
image favorites -> context.to(AppPageRoute(...Reader...))
```

Each entrypoint can accidentally create different route metadata, labels,
request shape, observer coverage, or lifecycle behavior.

Better pattern:

```text
UI entrypoint
  -> AppRouter.openReader(ReaderOpenRequest)
  -> one route factory
  -> one diagnostic contract
  -> one navigator target
```

#### Route construction and route observation must be connected

It is not enough to log inside `ReaderWithLoading`.

Reader logs can show:

```text
routeHash=297005604
label=ReaderWithLoading
```

But if `NaviObserver` never sees that route, then the app cannot answer:

- Who pushed it?
- Who popped it?
- Was it replaced?
- Was it hosted inside another route?
- Was it using a nested navigator?

Route creation and route lifecycle observation need a shared identity contract.

#### Diagnostics cannot fix unclear ownership

Adding more logs helped find the issue, but it also exposed that the
architecture has no single routing owner.

Diagnostics should verify architecture. They should not become the
architecture.

If every new bug requires another diagnostic patch, the module boundary is
probably wrong.

#### `ReaderOpenRequest` helped, but it only solved request identity

`ReaderOpenRequest` fixed source identity and the reader-open contract:

- `comicId`
- `sourceRef`
- `sourceKey` authority
- `chapterId`
- `page`
- `entrypoint`
- `caller`

But it does not own route lifecycle.

So the system now has a clean reader request contract, but still lacks a clean
reader route contract.

These are different layers.

## 2. Class and Model Ownership Is Scattered

The routing problem is not isolated.

The project also has a similar issue with class and model placement. Models and
helper classes are spread across `pages/`, `foundation/`, `features/`, and
`utils/`. This makes it hard to know which module owns a concept.

Observed pattern:

```text
pages/...          UI widget + page-local VM + helper model
foundation/...     shared runtime objects + app-wide services
features/...       feature repositories + domain-ish models
utils/...          import/parser/runtime helpers
```

This creates several risks:

- duplicate model shapes for the same concept
- UI models becoming runtime authority by accident
- repository DTOs leaking into widgets
- helper classes becoming hidden service layers
- tests importing page-local classes as if they are stable contracts

### Example Pattern

Bad structure:

```text
comic detail page owns a request/helper class
history page creates a similar route payload
local comic model creates another reader payload
reader page normalizes all of them again
```

This means the app has no clear answer to:

- Who owns `ReaderOpenRequest`?
- Who owns `ComicDetailVm`?
- Who owns `ReadingProgressVm`?
- Who owns `SourceRef`?
- Who owns source package metadata?

### Better Rule

Use ownership-based placement:

```text
Feature/domain contract:
  lib/features/<feature>/domain/...
Data/repository DTO:
  lib/features/<feature>/data/...
Presentation VM:
  lib/features/<feature>/presentation/...
Page-only widget state:
  lib/pages/... only if it is not imported outside that page
Cross-feature foundation type:
  lib/foundation/... only if truly app-wide and stable
```

### Practical Boundary Rule

A class should live near the layer that owns its truth.

- If it defines reader open identity -> reader feature
- If it defines comic detail display state -> comic_detail feature
- If it defines source repository package state -> source_management feature
- If it only helps one widget render -> same page/widget file
- If more than one feature imports it -> move it out of `pages/`

## 3. Storage Authority Is Scattered

Another lesson is that storage authority is also scattered.

The app has multiple database, file, and storage surfaces:

```text
venera.db
local.db / legacy local DB
history.db / legacy history DB
appdata.settings
appdata.implicitData
runtime JSON/cache files
source repository registry
reader session store
```

The problem is not simply "many DBs". The real problem is that different
functions can treat different stores as authority.

Observed risk:

```text
import function checks one DB
detail page reads another store
history reads a compatibility snapshot
reader resumes from reader_sessions
source page reads registry but old startup code rewrites appdata
```

This creates a "one function, one DB" pattern.

Each feature works locally, but the whole system has no single truth.

### What We Learned

A storage surface should not become authoritative just because a function can read it.

For each domain, there must be one declared authority:

```text
local library        -> canonical comic detail/local store
reader progress      -> canonical reader_sessions
source repositories  -> canonical repository registry
UI preferences       -> appdata/settings, if non-authoritative
device integration   -> appdata/implicitData, if local runtime state
legacy data          -> read-only fallback only
```

Bad pattern:

```text
Function A reads appdata
Function B reads legacy DB
Function C reads venera.db
Function D writes runtime JSON
All of them describe the same user-visible state
```

This creates bugs where every screen looks technically correct from its own
store, but the app state is inconsistent.

Better pattern:

```text
Domain authority first
compatibility fallback second
UI cache last
```

Example:

```text
Reader resume:
1. canonical reader_sessions
2. explicit legacy fallback
3. miss
```

Not:

```text
Sometimes appdata flag
Sometimes history manager
Sometimes reader_sessions
Sometimes page local state
```

### Rule Going Forward

Every storage-backed feature needs an authority table:

```text
Domain | Canonical Authority | Allowed Fallback | Forbidden Source | Migration State
```

Before adding a new storage read, ask:

```text
Is this authority, fallback, cache, preference, or diagnostic-only?
```

If the answer is unclear, do not add the read path yet.

## 4. Logs Need Decision-Useful Evidence

The project already has logs and diagnostics, but not all logs are useful for
debugging.

A log can contain information and still fail to answer the real question.

Example:

```text
reader.dispose.short_lived
image.provider.notSubscribed
reader.session.load.hit
```

These events are useful, but earlier versions did not answer:

- Who owned the route?
- Which entrypoint opened the reader?
- Was the tab still retained?
- Did Navigator observe the same route?
- Was the parent disposed by route pop, replacement, or subtree rebuild?

So the log had data, but not enough decision context.

### What We Learned

Good diagnostics should answer a decision question.

Bad diagnostic:

```text
Reader disposed
```

Better diagnostic:

```text
Reader disposed while:
- activeReaderTabId == expectedReaderTabId
- retainedTab=true
- branch=content
- routeHash=...
- entrypoint=comic_detail.continue
- parentStateHash=...
- navigator lifecycle correlation=missing
```

The second version tells us what to stop investigating.

### Debug-Useful Logs Need Four Things

1. Identity
   Which object, route, request, or store?
2. Authority
   Which source of truth was used?
3. Lifecycle
   What phase happened before and after?
4. Correlation
   Can this event be linked to related events?

Bad pattern:

```text
event=load.success
pageCount=16
```

This says the load worked, but it does not tell:

- which reader request
- which route
- which tab
- which entrypoint
- which storage authority
- which previous event

Better pattern:

```text
event=pageList.load.success
readerTabId=...
sourceRefId=...
requestEntrypoint=...
routeHash=...
correlationId=...
authority=canonical
```

### Rule Going Forward

Do not add logs just because something happened.

Add logs because they answer one of these questions:

- Should we blame routing?
- Should we blame storage authority?
- Should we blame async race?
- Should we blame UI state replacement?
- Should we blame parser/install command?

If a log cannot help eliminate a branch in the debug decision tree, it is
probably noise.

## Related Design Issue: Legacy Logs and Structured Diagnostics Are Split

The app currently has two logging surfaces:

```text
legacy logs        human-readable title/content records
structured logs    channel/message/data diagnostics records
```

The old logging path is useful for basic messages, but it does not reliably
carry the same identity, authority, lifecycle, and correlation fields as the
newer diagnostics API.

This creates a split:

```text
legacy log says something happened
structured diagnostic explains why it matters
```

For debugging, these two should not diverge.

### Direction

Legacy logs should either:

1. become a thin compatibility view over structured diagnostics
2. include the same correlation fields when recording runtime events

The long-term rule is:

```text
one runtime event -> one structured diagnostic record -> optional legacy display
```

Not:

```text
one event -> separate legacy log + separate structured log with different payload
```

### Required Fields for Important Runtime Events

- `channel`
- `message`
- `level`
- `timestamp`
- `identity`
- `authority`
- `lifecycle phase`
- `correlationId`
- `entrypoint` / `caller` where relevant

Legacy UI/export can still show simplified text, but the source record should
be structured.

## 5. Cleanup Strategy: Inventory First, Migration Second

The root issue is ownership sprawl, not one isolated bug.

The current design mixes routing ownership, model ownership, storage authority,
and diagnostics shape across many files and layers.

There is no single place that owns:

- route creation
- navigator selection
- route diagnostics
- feature contracts
- storage authority
- debug correlation rules

Without that rule, fixes keep leaking across module boundaries.

### Start With Inventory

Do not rewrite the whole router immediately.

Do not move all models immediately.

Do not merge storage cleanup into reader debugging lanes.

Start with inventories and narrow centralization.

#### Routing inventory

```text
R-routing-inventory-1
- find all context.to(...)
- find all Navigator.push(...)
- find all AppPageRoute(...)
- find reader/detail/history/source entrypoints
- classify root navigator vs nested navigator vs dialog/overlay
- document observer coverage
```

#### Model inventory

```text
M-model-inventory-1
- list classes declared under pages/
- list classes declared under utils/
- list cross-feature imports from pages/
- identify duplicated concepts:
  - reader request
  - comic detail VM
  - reading progress
  - source package metadata
  - local import metadata
- mark owner module for each
- no behavior change
```

#### Storage authority inventory

```text
ST-storage-authority-inventory-1
- list each user-visible domain state
- map canonical authority
- map compatibility fallback
- map cache/preference/diagnostic-only readers
- identify forbidden writes and ambiguous authority reads
- no behavior change
```

#### Log unification inventory

```text
L-log-unify-1
- inventory legacy log writes vs structured diagnostics writes
- classify which logs are UI notification vs runtime diagnostic
- design adapter: legacy Log.add(...) -> structured diagnostics mirror
- no behavior change
```

### Then Do Narrow Migrations

#### Reader route facade

This is a conceptual sketch, not a final API.

```dart
class AppRouter {
  static Future<T?> openReader<T>(
    BuildContext context,
    ReaderOpenRequest request,
  ) {
    // one place to build AppPageRoute
    // one place to set route label
    // one place to emit route diagnostic metadata
    // one place to choose navigator target
  }
}
```

UI code should become:

```dart
AppRouter.openReader(context, request);
```

not:

```dart
context.to(
  () => ReaderWithLoading.fromRequest(
    request: request,
  ),
);
```

#### Small model moves

```text
M-model-1
- move ReaderOpenRequest to reader contract module if not already there
- expose stable import path
- update imports only
- no behavior change

M-model-2
- move comic detail VMs into features/comic_detail/presentation or data boundary
- pages only consume VM, not define it

M-model-3
- move source install / package metadata into features/sources/comic_source
- source page only renders controller state
```

#### Small storage moves

```text
ST-storage-1
- declare authority table for reader/domain storage
- convert ambiguous reads into explicit fallback helpers
- forbid new direct legacy reads outside migration boundary
- no behavior change first
```

## Rule Going Forward

For critical flows, avoid this:

```text
UI page owns route construction
```

Use this instead:

```text
UI page owns intent
routing module owns navigation
feature module owns request contract
observer owns lifecycle recording
```

Avoid this model pattern:

```text
A page defines a model that other modules import
```

Prefer this:

```text
Feature module defines contract
Page imports contract and renders it
```

For storage-backed domains, avoid this:

```text
One function, one DB
```

Prefer this:

```text
One domain, one declared authority
Compatibility fallback is explicit
Cache/preference is never mistaken for authority
```

If a class crosses a page boundary, it is no longer page-local.

If a storage read crosses an authority boundary, it must be labeled as
authority, fallback, cache, preference, or diagnostic-only.

If a diagnostic cannot help eliminate a debug branch, it is probably noise.

## Practical Lesson

The reader issue exposed routing ownership problems first, then revealed the same
ownership weakness in model placement, storage authority, and diagnostics design.

Short-term convenience created long-term ambiguity about who owns truth.

The next architectural improvement should not be "more reader patches" or
"move models everywhere".

It should be:

```text
centralize reader navigation first
inventory model ownership second
declare storage authority third
reduce legacy/structured log drift fourth
improve decision-useful diagnostics continuously
migrate narrow slices gradually
```

## Related Follow-up

Keep appdata startup residue cleanup separate from the reader routing lane:

```text
A-appdata-cleanup-1: remove comicSourceListUrl startup rewrite residue from init.dart
```
