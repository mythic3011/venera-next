import { describe, expect, it } from "vitest";

import * as runtimeCore from "../../src/index.js";

describe("source contract export surface", () => {
  it("exports validator utilities without installer-oriented APIs", () => {
    expect(runtimeCore.validateSourceRepositoryIndex).toBeTypeOf("function");
    expect(runtimeCore.validateSourcePackageManifest).toBeTypeOf("function");
    expect(runtimeCore.validateSourcePackageChecksums).toBeTypeOf("function");
    expect(runtimeCore.validateCanonicalTags).toBeTypeOf("function");
    expect(runtimeCore.validateLocalizedTagLabels).toBeTypeOf("function");
    expect(runtimeCore.validateProviderTagMapping).toBeTypeOf("function");

    expect("installSourcePackage" in runtimeCore).toBe(false);
    expect("downloadSourcePackage" in runtimeCore).toBe(false);
    expect("runSourceVerifier" in runtimeCore).toBe(false);
    expect("createSourceSandbox" in runtimeCore).toBe(false);
  });
});
