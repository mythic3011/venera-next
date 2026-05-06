# Implementation Roadmap

**Status**: Architecture finalized, Rust core initialized  
**Date**: May 5, 2026

---

## Phase 1: Complete ✅

**Architecture Design**
- ✅ 5-layer canonical architecture defined
- ✅ 5 JSON schemas created (data contracts)
- ✅ Security boundaries documented
- ✅ Testing strategy defined
- ✅ Tech stack decided (Rust + Flutter)

**Location**: 
- Architecture: `/docs/plans/canonical-runtime-architecture.md`
- Tech stack: `/docs/plans/tech-stack-decision.md`
- Schemas: `/schemas/*.json`

---

## Phase 2: In Progress 🚀

**Rust Core Runtime (`venera-core/`)**
- ✅ Project initialized with Cargo
- ✅ Dependencies configured (Tokio, SQLx, Tonic, Serde)
- ✅ 5-layer module structure created
- ✅ Main daemon entry point
- ✅ Compilation verified

**Next Steps**:

### 2.1 Domain Models
- [ ] Implement Comic, Chapter, Page models
- [ ] Implement ReaderSession, SourcePlatform
- [ ] Add validation constraints
- [ ] Tests for invariants

### 2.2 Database Layer
- [ ] SQLx migrations (from canonical-db-model)
- [ ] Schema validation
- [ ] Connection pooling
- [ ] Query builders

### 2.3 Repository Implementations
- [ ] ComicRepository
- [ ] ChapterRepository
- [ ] ReaderSessionRepository
- [ ] PageRepository

### 2.4 Use Cases
- [ ] OpenReader use case
- [ ] SavePosition use case
- [ ] SearchComics use case
- [ ] ListChapters use case
- [ ] Transaction management

### 2.5 IPC Protocol
- [ ] Protocol buffer definitions
- [ ] Tonic gRPC server
- [ ] Message serialization
- [ ] Flutter integration stubs

---

## Phase 3: Flutter Integration (Deferred)

**Integration with Frontend**:
- [ ] FFI bindings to venera-core library
- [ ] IPC client in Dart
- [ ] Message marshalling
- [ ] State synchronization
- [ ] Error handling

---

## Phase 4: Gradual Migration (Deferred)

**Extract from Legacy**:
- [ ] Identify migrationable code
- [ ] Build extraction utilities
- [ ] Replace legacy modules
- [ ] Complete cutover

---

## Directory Structure

```
/
├── venera/                           # Flutter frontend
│   ├── lib/
│   │   ├── presentation/             # UI widgets
│   │   ├── application/              # State notifiers
│   │   ├── runtime_bridge/           # IPC to Rust
│   │   └── legacy/                   # Quarantined code
│   ├── docs/plans/
│   │   ├── canonical-runtime-architecture.md
│   │   └── tech-stack-decision.md
│   └── schemas/                      # JSON schemas
│
└── venera-core/                      # Rust core runtime
    ├── src/
    │   ├── application/              # Use cases
    │   ├── domain/                   # Models
    │   ├── ports/                    # Interfaces
    │   ├── infrastructure/           # Implementations
    │   ├── ipc/                      # IPC server
    │   └── diagnostics/              # Logging
    └── Cargo.toml
```

---

## Success Criteria

- [ ] Rust core compiles cleanly
- [ ] Domain models implement validation
- [ ] Database queries use SQLx (type-safe)
- [ ] Repository implementations follow Ports interfaces
- [ ] Use cases orchestrate without business logic in Presentation
- [ ] IPC enables Flutter ↔ Rust communication
- [ ] No legacy imports in canonical code
- [ ] All schemas validated at runtime
- [ ] Tests cover all layers (unit, integration)
- [ ] Documentation up-to-date

---

## Timeline Estimate

- **Phase 2.1-2.3** (Domain + DB): 2-3 weeks
- **Phase 2.4-2.5** (Use Cases + IPC): 2 weeks  
- **Phase 3** (Flutter Integration): 1-2 weeks
- **Phase 4** (Migration): Ongoing

---

## Risk Mitigation

- **Separated Concerns**: 5-layer architecture minimizes coupling
- **Type Safety**: Rust compile-time guarantees prevent many errors
- **Validated Data**: Schemas ensure contract enforcement
- **Comprehensive Tests**: Multiple test layers catch issues early
- **Gradual Migration**: Legacy code remains available for reference

---

## Runtime/Core Foundation Correction

For the current pre-stable `runtime/core` foundation slice, treat `normalizedTitle` as a non-unique search key, keep `CreateCanonicalComic` idempotency claim/create/replay inside one transaction, replay only completed results through a strict public DTO mapper, persist diagnostics events with `schemaVersion = "1.0.0"`, and keep boundary tests blocking Kysely, SQLite, DB schema, repository adapters, and legacy imports from `src/domain`, `src/application`, and `src/ports`.

Success criteria for this slice also require that rollback never leaves a completed idempotency record behind.

---

## Next Immediate Step

Begin Phase 2.1: Implement domain models in Rust matching schema definitions.

Location: `venera-core/src/domain/models/`
