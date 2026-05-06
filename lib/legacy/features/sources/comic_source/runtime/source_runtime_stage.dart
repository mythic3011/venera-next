/// Phase 1 intentionally keeps runtime stages minimal.
///
/// Broader stage taxonomy described in architecture documents is deferred
/// to later phases and is not implemented here.
enum SourceRuntimeStage { legacy, request, parser }
