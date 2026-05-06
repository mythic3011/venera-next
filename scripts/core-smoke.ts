import {
  parseSmokeArgs,
  runCoreSmoke,
} from "../runtime/core/src/cli/dev-smoke.js";

async function main(argv: readonly string[] = process.argv.slice(2)): Promise<void> {
  const result = await runCoreSmoke(parseSmokeArgs(argv));

  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.ok ? 0 : 1;
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Runtime core smoke wrapper failed unexpectedly.";
  console.error(message);
  process.exitCode = 1;
});
