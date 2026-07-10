# Source packages and tag taxonomy

## Canonical installation

V1 source installation accepts verified repository/package artifacts, not raw
one-file JavaScript source definitions:

```text
repository index
  -> package entry
  -> built archive
  -> integrity verification
  -> manifest validation
  -> runtime-entrypoint validation
  -> install/update mutation
  -> registration by providerKey
```

An installation must fail closed before mutation when the artifact has a hash
mismatch, missing entrypoint, unsupported runtime API, provider-key mismatch, or
invalid taxonomy data.

The identity rules are:

```text
providerKey  = immutable runtime identity
displayName  = mutable UI label
manifest     = runtime contract
index        = discovery/install/update catalogue
artifact     = accepted canonical install input
```

The package artifact may contain TypeScript modules, helpers, tests, and mapping
data during development, but the installed form must expose a validated manifest,
runtime entrypoint, and integrity metadata.

## Runtime boundary

Source extensions are constrained provider logic. They may call only the runtime
API exposed for the package, for example:

```text
ctx.net, ctx.parse, ctx.url, ctx.text, ctx.diagnostics, ctx.manifest
```

They must not directly access the filesystem, database, cookie store, storage
adapters, environment variables, process APIs, or unrestricted network APIs.

## Tags and localization

Extensions return provider tags. Canonical identity, provider mappings, and
localized labels are data contracts:

```text
taxonomy/canonical-tags.json
taxonomy/labels/<locale>.json
taxonomy/mappings/<providerKey>.<locale>.json
```

Tags should carry namespace, facet, and value-type information so genre,
audience, year, language, warning, author, artist, and provider-specific values
remain distinguishable.

V1 does not use display-name identity matching, automatic provider renames,
provider lineage aliases, automatic canonical-tag merging, or hard-coded
cross-platform translation in extension code.
