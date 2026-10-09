import test from "node:test";
import assert from "node:assert/strict";
import { buildDockerArgs, SandboxError } from "../docker-sandbox.mjs";

const clean = {
  selectedDir: "/tmp/old-venera",
  appDir: "/tmp/import-app",
  containerName: "venera-legacy-0123456789abcdefabcd",
  uid: 1000,
  gid: 1000,
};
test("sandbox removes network, writable host/root and Linux capabilities", () => {
  const args = buildDockerArgs(clean);
  assert.deepEqual(args.slice(0,2), ["run","--rm"]);
  for (const must of [
    "--network=none", "--read-only", "--cap-drop=ALL",
    "--security-opt=no-new-privileges", "--pull=never", "--pids-limit=64",
    "--memory=512m", "--cpus=1", "--user", "1000:1000",
    "type=bind,src=/tmp/old-venera,dst=/legacy,readonly",
    "type=bind,src=/tmp/import-app,dst=/app,readonly",
    "/app/preview.mjs", "--dir", "/legacy"
  ]) assert.ok(args.includes(must), "missing sandbox rule: " + must);
  assert.ok(!args.includes("--privileged"));
  assert.ok(!args.includes("--network=host"));
  assert.ok(!args.some(x=>x.includes("docker.sock")));
});
test("sandbox cannot invoke shell, select arbitrary image or elevate root", () => {
  const bad = [
    { ...clean, uid: 0 },
    { ...clean, gid: 0 },
    { ...clean, image: "node:latest" },
    { ...clean, selectedDir: "/tmp/old,evil" },
    { ...clean, appDir: "relative/path" },
    { ...clean, containerName: "hijacked" },
  ];
  for(const input of bad)
    assert.throws(()=>buildDockerArgs(input), SandboxError);
});
