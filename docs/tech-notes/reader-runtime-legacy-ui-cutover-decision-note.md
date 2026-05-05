# Reader Runtime / Legacy UI Cutover Decision Note

## Context

I originally thought the main problem was the reader runtime.

The reader had black screen problems, unstable resume behavior, unresolved local reader targets, session persistence races, and legacy appdata fallback mixed into the live reader path. Therefore, I spent a lot of effort fixing the runtime layer first:

- canonical reader session design
- `ReaderOpenTarget` / `ReaderOpenRequest`
- route-boundary validation
- local imported chapter resolution
- flat local comic fallback chapter
- DB / session dedupe
- lifecycle diagnostics
- removal of legacy resume fallback from the live runtime

After these fixes, the new runtime became mostly usable. The data path could resolve targets, load page lists, decode images, and persist sessions correctly.

However, after the runtime was fixed, the remaining bugs kept coming from the old UI and routing layer.

The old UI was still building or passing legacy reader identity. It still carried old assumptions about comic type, route target, resume state, and appdata compatibility. Every time one runtime issue was fixed, another bug appeared through the old UI / routing path.

This shows that the problem was not only the runtime. The real problem was the mixed legacy boundary between UI, routing, reader state, storage, and rendering.

---

## What I Discovered

The old reader stack was not separated cleanly.

Different layers were all trying to control or repair reader identity:

- UI built reader route identity
- route layer accepted incomplete `SourceRef`
- `ReaderWithLoading` repaired missing chapter identity
- session layer tried to restore active tab
- appdata / `implicitData` acted as legacy resume fallback
- comic type mixed local / remote / imported / source / storage / runtime meaning
- diagnostics sometimes downgraded real invalid state into harmless pending state

This created a mixed-authority system.

Instead of having one clear source of truth, many layers could mutate, infer, or repair reader state.

That means the bugs were not isolated. A black screen could be caused by route identity, legacy resume fallback, missing chapter model, appdata state, session race, Hero / Overlay behavior, or stale UI assumptions.

This made debugging extremely expensive.

---

## Previous Assumption

My previous assumption was:

> Once the runtime is fixed, the UI should mostly be fine.

This assumption was wrong.

The UI was not just a thin display layer. It was part of the legacy runtime behavior.

The old UI did not simply call the runtime. It carried old routing contracts, old comic type assumptions, old `SourceRef` construction, and old resume behavior.

So even if the runtime became correct, the UI could still inject invalid state into it.

In other words:

> I assumed the UI was only a consumer of the runtime.  
> In reality, the UI was still an authority over runtime identity.

That was the core wrong assumption.

---

## Why the Assumption Was Wrong

The old UI / routing layer was still allowed to do things that should only belong to the canonical runtime resolver.

Examples:

- UI or route code could create `local:local:<comicId>:_`
- local first-open could reach dispatch without a resolved chapter id
- old resume fallback could re-enter through appdata
- `ReaderWithLoading` could repair identity after the parent shell already existed
- comic type flags were used to infer runtime behavior
- diagnostics could hide unresolved target problems as pending state

These are not UI responsibilities.

A correct UI should only send user intent:

- Start reading
- Continue reading
- Open chapter
- Go to page

It should not decide:

- `SourceRef` id
- reader tab id
- canonical chapter id
- resume fallback source
- local / remote runtime behavior
- appdata compatibility

That responsibility belongs to the canonical resolver and runtime.

---

## Lesson Learned

The main lesson is:

> Do not let legacy UI and new runtime coexist through an unclear boundary.

A rebuilt runtime cannot stay reliable if the old UI can still inject legacy identity into it.

The issue was not one reader bug. It was a boundary problem.

The old reader stack had UI, routing, resume state, appdata, comic type, and rendering all mixed together. Every layer had partial authority. That made each fix create or reveal another bug.

The rule going forward is:

- UI sends intent only
- resolver owns identity
- runtime owns loading
- DB owns durable state
- diagnostics report violations
- legacy code owns nothing in the live runtime

If a legacy path cannot follow this boundary, it should be cut off, not patched.

---

## Why I Am Making This Decision

I am choosing to cut off the old UI / routing path because continuing to patch it is no longer efficient.

The project has already spent too much effort fixing symptoms caused by legacy cross-contamination. The old stack repeatedly reintroduced invalid state into the new runtime.

At this point, maintaining compatibility with the legacy UI / runtime path costs more than rebuilding a clean entrypoint around the working runtime.

The new direction is:

> Runtime first, canonical only, then build a clean minimal UI entrypoint on top.

Old UI behavior, legacy resume compatibility, appdata fallback, and old comic type inference should not remain inside the live reader path.

If old progress or favorites need to be preserved, they can be handled later through JSON import / export or one-shot migration tools. They should not block the runtime cutover.

---

## New Decision

The reader will move to a canonical-only runtime path.

The old UI / routing path should be treated as untrusted.

The new reader entry flow should be:

```text
UI intent
  -> ReaderOpenTargetResolver
  -> resolved ReaderOpenTarget
  -> validated ReaderOpenRequest
  -> canonical reader runtime
  -> pageList load
  -> image provider
  -> decode / render
  -> canonical reader session persistence
```

The old flow should be removed or blocked:

```text
UI builds SourceRef
  -> route accepts incomplete identity
  -> ReaderWithLoading repairs chapter
  -> legacy resume fallback reads appdata
  -> session repairs active tab
  -> diagnostics hides invalid state
```

This old flow is the source of repeated bugs.

---

## Final Position

This is not about expecting open-source code to be perfect.

The problem is that the old code has no clean authority boundary. It mixes UI, runtime, route identity, storage, resume, and comic type logic together.

That is why the fixes kept multiplying.

The correct decision is to stop repairing the legacy UI / runtime boundary and instead expose the working runtime through a clean new entrypoint.

The old UI should not be trusted as a runtime boundary anymore.

---

## Short Version

I originally assumed the UI was only broken at the surface. That was wrong.

The old UI was still part of the legacy runtime authority. It could build route identity, infer comic type, trigger legacy resume fallback, and inject invalid `SourceRef` into the new runtime.

Therefore, fixing the runtime alone was not enough.

The correct decision is to cut off the old UI / routing path and rebuild a minimal canonical entrypoint where UI sends intent only and the runtime resolver owns all reader identity.
