import type { createRuntimeAdapter } from "../adapter/runtime-adapter.js";

export type RuntimeAdapter = ReturnType<typeof createRuntimeAdapter>;
