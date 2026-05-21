# Historical Rust-First Tech Stack Proposal

> **Superseded note:** This is a historical Rust-first planning artifact. Current canonical runtime authority is the TypeScript-first `runtime/core` surface plus `docs/design/**`. The root `schemas/` directory is not current canonical runtime authority.

**Status**: Historical planning artifact (superseded)
**Branch**: `architecture/canonical-skeleton`  
**Date**: May 5, 2026  
**Language Decision**: Rust (core runtime) + Flutter (frontend)

---

## Original Tech Stack Proposal

### Frontend In The Proposal
- **Flutter** — UI layer, platform-specific (iOS/Android/macOS/Linux/Windows)
- **Dart** — UI logic, navigation, state management
- **Rationale**: Existing investment, proven mobile capability

### Core Runtime In The Proposal
- **Rust** — Core data layer, business logic, system integration
- **Tokio** — Async runtime for concurrent operations
- **Sqlx** — Type-safe database access with compile-time verification
- **Serde** — JSON serialization/deserialization
- **Rationale**: Performance, memory safety, excellent server runtime, WebAssembly-ready

### IPC In The Proposal
- **Protocol Buffers** or **MessagePack** — Serialization between Flutter ↔ Rust
- **Channels**: Named pipes (macOS/Linux), TCP localhost (all platforms)

---

## Architecture Shape In The Proposal

The proposal kept the same 5 layers while changing implementation language:

```
┌──────────────────────────────────┐
│ Presentation Layer (Dart/Flutter)│  ← UI, navigation, state notifiers
├──────────────────────────────────┤
│ IPC Boundary                     │  ← Protocol buffers / MessagePack
├──────────────────────────────────┤
│ Application Layer (Rust)         │  ← Use cases, orchestration
├──────────────────────────────────┤
│ Domain Layer (Rust)              │  ← Models, business rules
├──────────────────────────────────┤
│ Ports Layer (Rust)               │  ← Repository interfaces
├──────────────────────────────────┤
│ Infrastructure Layer (Rust)      │  ← Database, file I/O, network
├──────────────────────────────────┤
│ Legacy Code (Dart, read-only)    │  ← Reference only
└──────────────────────────────────┘
```

---

## Project Structure

### Flutter Frontend (Dart)
```
lib/
├── main.dart                        # Entry point
├── presentation/                    # UI widgets, screens
├── application/                     # State notifiers, coordinators
├── runtime_bridge/                  # IPC to Rust core
└── legacy/                          # Quarantined old code
```

### Rust Core Runtime
```
venera-core/                         # New Rust crate
├── Cargo.toml
├── src/
│   ├── main.rs                      # Daemon/server entry
│   ├── lib.rs                       # Library interface
│   ├── application/                 # Use cases
│   ├── domain/                      # Models, business logic
│   ├── ports/                       # Repository traits
│   ├── infrastructure/              # Database, adapters
│   │   ├── db/                      # SQLx database layer
│   │   ├── fs/                      # File system operations
│   │   └── http/                    # HTTP clients
│   ├── ipc/                         # IPC protocols (protobuf/msgpack)
│   └── diagnostics/                 # Structured logging, tracing
└── tests/                           # Rust tests
```

### Shared Definitions
```
schemas/                             # Historical prototype JSON schemas
proto/                               # Protocol buffer definitions
├── diagnostics.proto
├── source_manifest.proto
├── reader_events.proto
└── app_settings.proto
```

---

## Benefits of Rust Runtime

| Concern | Dart-only | Rust + Flutter |
|---------|-----------|-----------------|
| **Performance** | Moderate | Excellent (systems language) |
| **Memory Safety** | GC managed | Compile-time safety |
| **Concurrency** | Good | Excellent (Tokio) |
| **Database** | Limited ORMs | Type-safe Sqlx |
| **Mobile Integration** | Native plugins | Direct system access |
| **WebAssembly** | Limited | Native support |
| **Backend Deployment** | Awkward | Natural fit |
| **Code Sharing** | N/A | Protocols bridge frontend |

---

## Implementation Phases

### Phase 1: Core Runtime Skeleton (Rust)
- [ ] Cargo workspace setup
- [ ] IPC protocol definition (protobuf)
- [ ] Async runtime initialization (Tokio)
- [ ] Basic message passing (Flutter ↔ Rust)

### Phase 2: Database Layer (Rust)
- [ ] SQLx migrations (from canonical-db-model)
- [ ] Domain model implementations
- [ ] Repository trait implementations

### Phase 3: Business Logic (Rust)
- [ ] Use cases and coordinators
- [ ] Security boundaries enforcement
- [ ] Diagnostics integration

### Phase 4: Flutter Integration
- [ ] FFI bindings to Rust library
- [ ] IPC message handling in Dart
- [ ] State synchronization

### Phase 5: Gradual Migration
- [ ] Extract legacy Dart code to Rust
- [ ] Deprecate legacy business logic
- [ ] Complete cutover

---

## Schema Status

The 5 JSON schemas under `schemas/` are historical prototypes only.

They are not the current canonical contracts:
- Protocol buffer definitions do not currently derive from these schemas
- Current runtime/core validation authority lives in TypeScript contracts and validators
- Diagnostics authority lives in `runtime/core/src/domain/diagnostics.ts` and `docs/design/diagnostics-events.md`
- Source package / repository authority lives in `runtime/core/src/source-contracts/validators.ts`

---

## Security Model Enhanced

Rust provides:
- **Memory safety**: No buffer overflows, no use-after-free
- **Thread safety**: Compile-time data race prevention
- **Type safety**: Exhaustive pattern matching on domain types

JS sandbox and permission model remain unchanged.

---

## Next Steps

1. **Create Rust workspace** (`venera-core/`)
2. **Define IPC protocols** (protobuf)
3. **Implement async runtime** with Tokio
4. **Build core skeleton** with message passing
5. **Migrate DB layer** from Dart to Rust
6. **Gradual feature cutover** from legacy Dart to Rust
