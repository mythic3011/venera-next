import { mkdtemp, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import type { BoundaryConfig } from "../../src/scripts/boundary-scan.js";
import { scanBoundaries } from "../../src/scripts/boundary-scan.js";

const createdRoots: string[] = [];

async function createFixture(structure: Record<string, string>): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "venera-boundary-"));
  createdRoots.push(root);

  for (const [filePath, contents] of Object.entries(structure)) {
    const absolutePath = join(root, filePath);
    await mkdir(join(absolutePath, ".."), { recursive: true });
    await writeFile(absolutePath, contents, "utf8");
  }

  return root;
}

afterEach(async () => {
  await Promise.all(createdRoots.splice(0).map(async (root) => {
    await import("node:fs/promises").then(({ rm }) => rm(root, {
      force: true,
      recursive: true,
    }));
  }));
});

const config: BoundaryConfig = {
  files: [
    "src/**/*.ts",
    "src/**/*.tsx",
  ],
  rules: [
    {
      name: "client-must-not-import-server",
      from: [/^src\/client\//],
      forbidden: [/^src\/server\//],
    },
  ],
};

describe("boundary scan", () => {
  it("flags forbidden relative imports", async () => {
    const root = await createFixture({
      "src/client/widget.ts": "import '../server/api.js';\n",
      "src/server/api.ts": "export const value = 1;\n",
    });

    const violations = await scanBoundaries(config, root);
    expect(violations).toEqual([
      {
        file: "src/client/widget.ts",
        importSource: "src/server/api.ts",
        rule: "client-must-not-import-server",
        type: "forbidden_import",
      },
    ]);
  });

  it("fails non-literal dynamic imports", async () => {
    const root = await createFixture({
      "src/client/widget.ts": "const path = '../server/api.js';\nawait import(path);\n",
      "src/server/api.ts": "export const value = 1;\n",
    });

    const violations = await scanBoundaries(config, root);
    expect(violations).toEqual([
      {
        file: "src/client/widget.ts",
        importSource: "<dynamic>",
        rule: "dynamic-import-literal-only",
        type: "unanalyzable_dynamic_import",
      },
    ]);
  });
});
