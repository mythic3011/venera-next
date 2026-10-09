// Reference Linux/Docker OS-level boundary for the read-only L0 inspector.
// Docker daemon/image are TRUSTED inputs; legacy DB/JSON remain UNTRUSTED.
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { lstat, realpath, readFile, mkdtemp, chmod, rm } from "node:fs/promises";
import { dirname, resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { INPUT_ROLES } from "./l0.mjs";
import { sanitizeSandboxResult } from "./sanitize-result.mjs";

export class SandboxError extends Error {
  constructor(code) { super(code); this.name = "SandboxError"; this.code = code; }
}
function deny(code) { throw new SandboxError(code); }
export const DEFAULT_IMAGE = "node:22.16.0-bookworm-slim";
const APP_DIR = dirname(fileURLToPath(import.meta.url));
const MAX_OUTPUT_BYTES = 1024 * 1024;
const TIMEOUT_MS = 30_000;

function validatedMountPath(path) {
  if (typeof path !== "string" || !path.startsWith("/") ||
      /[,\x00-\x1f\x7f]/.test(path)) deny("SANDBOX_INVALID_MOUNT_PATH");
  return path;
}
export function buildDockerArgs({ selectedDir, appDir, containerName,
  image = DEFAULT_IMAGE, uid, gid, outputDir=null }) {
  validatedMountPath(selectedDir);
  validatedMountPath(appDir);
  if(outputDir!==null)validatedMountPath(outputDir);
  if (!/^venera-legacy-[a-f0-9]{20}$/.test(containerName)) deny("SANDBOX_INVALID_CONTAINER_NAME");
  if (!Number.isSafeInteger(uid) || !Number.isSafeInteger(gid) || uid <= 0 || gid <= 0)
    deny("SANDBOX_UNPRIVILEGED_USER_REQUIRED");
  if (typeof image !== "string" || !/^node:22\.16\.0-bookworm-slim$/.test(image))
    deny("SANDBOX_IMAGE_NOT_APPROVED");
  const args=[
    "run", "--rm", "--pull=never", "--name", containerName, "--network=none",
    "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
    "--pids-limit=64", "--memory=512m", "--memory-swap=512m", "--cpus=1",
    "--user", String(uid) + ":" + String(gid),
    "--tmpfs", "/tmp:rw,noexec,nosuid,nodev,size=96m,mode=1777",
    "--mount", "type=bind,src=" + appDir + ",dst=/app,readonly",
    "--mount", "type=bind,src=" + selectedDir + ",dst=/legacy,readonly",
  ];
  if(outputDir!==null)
    args.push("--mount","type=bind,src="+outputDir+",dst=/out");
  args.push("--workdir","/app","--env","NODE_ENV=production",image,"node");
  if(outputDir===null)args.push("/app/preview.mjs","--dir","/legacy");
  else args.push("/app/export-snapshots.mjs","--dir","/legacy","--out","/out");
  return args;
}
async function validateDirectory(dir) {
  if (typeof dir !== "string" || !dir.length) deny("SANDBOX_NO_DIRECTORY");
  // Do not silently follow an untrusted root symlink into an unrelated home directory.
  const absolute = resolve(dir);
  const st = await lstat(absolute).catch(() => deny("SANDBOX_INPUT_UNAVAILABLE"));
  if (!st.isDirectory() || st.isSymbolicLink()) deny("SANDBOX_INPUT_NOT_DIRECTORY");
  return validatedMountPath(await realpath(absolute));
}
function runDocker(args, { timeoutMs = TIMEOUT_MS, maxOutputBytes = MAX_OUTPUT_BYTES } = {}) {
  return new Promise((resolvePromise, rejectPromise) => {
    let stdout = "";
    let total = 0;
    let finished = false;
    const child = spawn("docker", args, {
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
      windowsHide: true,
      env: { PATH: process.env.PATH || "/usr/bin:/bin", HOME: process.env.HOME || "/" },
    });
    // Drain stderr without forwarding Docker's potentially sensitive host paths.
    child.stderr.on("data", () => {});
    child.stdout.on("data", chunk => {
      total += chunk.length;
      if (total > maxOutputBytes) {
        child.kill("SIGKILL");
        return;
      }
      stdout += chunk.toString("utf8");
    });
    const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
    child.once("error", () => {
      if (!finished) { finished = true; clearTimeout(timer); rejectPromise(new SandboxError("SANDBOX_DOCKER_UNAVAILABLE")); }
    });
    child.once("close", code => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      if (total > maxOutputBytes) return rejectPromise(new SandboxError("SANDBOX_OUTPUT_LIMIT"));
      if (code !== 0) return rejectPromise(new SandboxError("SANDBOX_EXECUTION_FAILED"));
      let data;
      try { data = JSON.parse(stdout); } catch { return rejectPromise(new SandboxError("SANDBOX_RESULT_INVALID")); }
      // Even an exploited parser process cannot return arbitrary strings to
      // the trusted UI. Only bounded, typed aggregate counters cross IPC.
      try { resolvePromise(sanitizeSandboxResult(data)); }
      catch { rejectPromise(new SandboxError("SANDBOX_RESULT_INVALID")); }
    });
  });
}
function cleanupContainer(name) {
  // Best-effort kill on timeout/execution error (docker run client may die earlier).
  // --rm handles normal completion. No shell and no user-controlled container name.
  const proc = spawn("docker", ["rm", "--force", name], {
    stdio: "ignore", shell: false, windowsHide: true
  });
  proc.on("error", () => {});
}
export async function previewInDocker(selectedDirectory) {
  if (!["linux","darwin"].includes(process.platform)) deny("SANDBOX_PLATFORM_UNSUPPORTED");
  const uid = process.getuid?.(), gid = process.getgid?.();
  if (!uid || !gid) deny("SANDBOX_UNPRIVILEGED_USER_REQUIRED");
  const selectedDir = await validateDirectory(selectedDirectory);
  const appDir = await validateDirectory(APP_DIR);
  const containerName = "venera-legacy-" + randomBytes(10).toString("hex");
  const args = buildDockerArgs({ selectedDir, appDir, containerName, uid, gid });
  try {
    return await runDocker(args);
  } catch (error) {
    cleanupContainer(containerName);
    throw error;
  }
}


// Host-private bridge from OS-isolated consistent snapshots to an in-memory
// lease. This is not an end-user Import Wizard or record-level authorization.
// Never return its leaseRef from a renderer/plugin RPC.
export async function previewAndIssueSnapshotLease({
  selectedDirectory,ownerScopeId,datasetId,snapshotLeaseRegistry
}) {
  if(!snapshotLeaseRegistry || typeof snapshotLeaseRegistry.issue!=="function")
    deny("SANDBOX_LEASE_REGISTRY_REQUIRED");
  if(!["linux","darwin"].includes(process.platform))
    deny("SANDBOX_PLATFORM_UNSUPPORTED");
  const uid=process.getuid?.(),gid=process.getgid?.();
  if(!uid||!gid)deny("SANDBOX_UNPRIVILEGED_USER_REQUIRED");
  const selectedDir=await validateDirectory(selectedDirectory);
  const appDir=await validateDirectory(APP_DIR);
  const outputDir=await mkdtemp(join(tmpdir(),"venera-lease-stage-"));
  await chmod(outputDir,0o700);
  const name="venera-legacy-"+randomBytes(10).toString("hex");
  const buffers=[];
  try {
    const args=buildDockerArgs({
      selectedDir,appDir,containerName:name,uid,gid,outputDir
    });
    const preview=await runDocker(args);
    if(preview.status!=="preview_only")deny("SANDBOX_LEASE_PREVIEW_INVALID");
    for(const record of preview.files) {
      if(record.status!=="inspected")continue;
      if(!INPUT_ROLES.includes(record.role))deny("SANDBOX_RESULT_INVALID");
      const path=join(outputDir,record.role);
      const st=await lstat(path);
      if(!st.isFile()||st.isSymbolicLink())deny("SANDBOX_LEASE_FILE_INVALID");
      const bytes=await readFile(path);
      buffers.push({role:record.role,bytes});
    }
    if(buffers.length!==preview.totals.inspected)
      deny("SANDBOX_LEASE_FILE_INVALID");
    const evidencePath=join(outputDir,".record-evidence.json");
    const evidenceInfo=await lstat(evidencePath);
    if(!evidenceInfo.isFile() || evidenceInfo.isSymbolicLink() ||
       evidenceInfo.size>32*1024*1024)
      deny("SANDBOX_LEASE_EVIDENCE_INVALID");
    const evidenceText=await readFile(evidencePath,"utf8");
    let evidence;
    try { evidence=JSON.parse(evidenceText); }
    catch { deny("SANDBOX_LEASE_EVIDENCE_INVALID"); }
    if(!evidence || evidence.version!==1 || !Array.isArray(evidence.proofs) ||
       Object.keys(evidence).sort().join(",")!=="proofs,version")
      deny("SANDBOX_LEASE_EVIDENCE_INVALID");
    const {leaseRef,expiresAt}=snapshotLeaseRegistry.issue({
      ownerScopeId,datasetId,inputs:buffers,recordProofs:evidence.proofs
    });
    return Object.freeze({preview,leaseRef,expiresAt});
  }catch(e){
    cleanupContainer(name);
    if(e instanceof SandboxError)throw e;
    deny("SANDBOX_SNAPSHOT_LEASE_FAILED");
  }finally{
    for(const record of buffers)record.bytes.fill(0);
    await rm(outputDir,{recursive:true,force:true});
  }
}
