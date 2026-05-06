# Canonical Runtime Architecture — Rust Implementation

**Status**: Architecture Baseline + Tech Stack Decision  
**Branch**: `architecture/canonical-skeleton`  
**Date**: May 5, 2026  
**Language Decision**: Rust (core runtime) + Flutter (frontend)

---

## Tech Stack Decision

### Frontend (Unchanged)
- **Flutter** — UI layer, platform-specific (iOS/Android/macOS/Linux/Windows)
- **Dart** — UI logic, navigation, state management
- **Rationale**: Existing investment, proven mobile capability

### Core Runtime (NEW)
- **Rust** — Core data layer, business logic, system integration
- **Tokio** — Async runtime for concurrent operations
- **Sqlx** — Type-safe database access with compile-time verification
- **Serde** — JSON serialization/deserialization
- **Rationale**: Performance, memory safety, excellent server runtime, WebAssembly-ready

### IPC (Inter-Process Communication)
- **Protocol Buffers** or **MessagePack** — Serialization between Flutter ↔ Rust
- **Channels**: Named pipes (macOS/Linux), TCP localhost (all platforms)

---

## Architecture Unchanged

All 5 layers remain identical; implementation language differs:

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
schemas/                             # JSON schemas (unchanged)
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

## Schemas Remain Valid

All 5 JSON schemas from `schemas/` remain the canonical contracts:
- Protocol buffer definitions compile from schemas
- Database migrations from canonical model
- IPC serialization validated against schemas

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
