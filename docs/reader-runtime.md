# Reader runtime, data model, and diagnostics

## Reader opening

The UI sends intent only. A canonical resolver must produce a validated reader
request before runtime execution:

```text
UI intent
  -> ReaderOpenTargetResolver
  -> ReaderOpenTarget
  -> ReaderOpenRequest
  -> reader runtime
  -> page loading and rendering
  -> canonical session persistence
```

The runtime must not repair incomplete identity or use placeholder IDs such as
`local:local:<comicId>:_`. Unresolved targets return typed failures and emit
structured diagnostics.

## Identity and storage

Encoded string references are debug projections, not authority. Database columns,
foreign keys, and typed domain objects own relationships:

```text
DB authority:       columns + foreign keys
Runtime authority:  typed domain objects
Debug view:         readable rendered references
```

Typical relationship fields include `comic_id`, `chapter_id`, `provider_id`,
`remote_work_id`, `page_index`, and `source_kind`. Runtime code should pass typed
objects such as `ReaderOpenTarget` instead of parsing a magic string.

## Diagnostics

Diagnostics should answer a decision question and identify the boundary that
rejected or accepted a request. Useful fields include identity, authority,
lifecycle phase, correlation, caller, and rejection reason.

```text
event=reader.route.unresolved_target
comic.id=<comicId>
source.kind=local
chapter.id=null
reason=missing_local_chapter
boundary=route.dispatch
action=rejected
```

Diagnostics report violations; they do not silently downgrade invalid identity
into pending state or mutate application state as a repair mechanism.
