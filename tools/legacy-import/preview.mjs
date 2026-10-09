#!/usr/bin/env node
// Explicit user-selected directory only: no autoscan, writes, migration or network.
import { previewLegacyDirectory, LegacyInspectionError } from "./l0.mjs";

function usage() {
  process.stderr.write("Usage: node tools/legacy-import/preview.mjs --dir /path/to/old-venera-data\n");
}
const argv = process.argv.slice(2);
if (argv.length !== 2 || argv[0] !== "--dir") {
  usage();
  process.exitCode = 2;
} else {
  try {
    const preview = await previewLegacyDirectory(argv[1]);
    process.stdout.write(JSON.stringify(preview, null, 2) + "\n");
    if (preview.status === "needs_attention") process.exitCode = 1;
  } catch (error) {
    const code = error instanceof LegacyInspectionError ? error.code : "LEGACY_INSPECTION_FAILED";
    // Never print raw input, path, SQLite exception text or parsed JSON.
    process.stderr.write(JSON.stringify({ status: "failed", code }) + "\n");
    process.exitCode = 1;
  }
}
