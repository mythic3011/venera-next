#!/usr/bin/env node
// Host-only launcher: never falls back from Docker isolation to direct execution.
import { previewInDocker, SandboxError } from "./docker-sandbox.mjs";
const argv = process.argv.slice(2);
if (argv.length !== 2 || argv[0] !== "--dir" || !argv[1]) {
  process.stderr.write("Usage: node tools/legacy-import/preview-isolated.mjs --dir /path/to/old-venera-data\n");
  process.exitCode = 2;
} else {
  try {
    const result = await previewInDocker(argv[1]);
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
    if (result.status === "needs_attention") process.exitCode = 1;
  } catch (e) {
    process.stderr.write(JSON.stringify({
      status: "failed",
      code: e instanceof SandboxError ? e.code : "SANDBOX_UNAVAILABLE"
    }) + "\n");
    process.exitCode = 1;
  }
}
