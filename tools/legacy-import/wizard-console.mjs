#!/usr/bin/env node
// Interactive LOCAL HOST terminal reference, NOT the finished Venera GUI.
// No headless --yes/--approve flag, no renderer/plugin HTTP endpoint.
// Existing canonical v2 database REQUIRED. NEVER create/migrate target schema.
import { DatabaseSync } from "node:sqlite";
import { lstat, realpath } from "node:fs/promises";
import { sep } from "node:path";
import { createTTYGestureAuthority } from "./trusted-gesture.mjs";
import { TrustedSnapshotLeaseRegistry } from "./snapshot-lease.mjs";
import { runTrustedEvidenceWizard } from "./trusted-wizard.mjs";

function failure(code,exitCode=1) {
  process.stderr.write(JSON.stringify({status:"failed",code})+"\n");
  process.exitCode=exitCode;
}
const args=process.argv.slice(2);
const fields=new Map();
let valid=args.length===6;
for(let i=0;i<args.length;i+=2) {
  const k=args[i],v=args[i+1];
  if(!["--source","--canonical-db","--dataset-label","--dataset-id"].includes(k) ||
     !v || fields.has(k))valid=false;
  fields.set(k,v);
}
if(!fields.has("--source") || !fields.has("--canonical-db") ||
   (fields.has("--dataset-label")===fields.has("--dataset-id")))valid=false;
if(!valid){
  failure("WIZARD_USAGE_INVALID",2);
} else {
  let db;
  try {
    // MUST be an actual trusted local tty with no programmatic acceptance
    // flag. This proves control of the trusted console, not OS user identity.
    const gestureAuthority=createTTYGestureAuthority();
    if(!["linux","darwin"].includes(process.platform) ||
       !process.getuid?.() || !process.getgid?.())
      throw new Error("WIZARD_HOST_UNSUPPORTED");
    const source=await realpath(fields.get("--source"));
    const inputStat=await lstat(fields.get("--source"));
    if(!inputStat.isDirectory() || inputStat.isSymbolicLink())
      throw new Error("WIZARD_SOURCE_INVALID");
    const targetStat=await lstat(fields.get("--canonical-db"));
    if(!targetStat.isFile() || targetStat.isSymbolicLink())
      throw new Error("WIZARD_TARGET_INVALID");
    const target=await realpath(fields.get("--canonical-db"));
    if(target===source || target.startsWith(source+sep))
      throw new Error("WIZARD_TARGET_INVALID");
    db=new DatabaseSync(target,{create:false});
    db.exec("PRAGMA foreign_keys=ON");
    // Refuse old-runtime/Unified-Store schema and databases without the
    // CANONICAL fresh-v2 legacy contract. No CREATE TABLE in this tool.
    const names=new Set(db.prepare(
      "SELECT name FROM sqlite_master WHERE type='table'"
    ).all().map(row=>row.name));
    for(const required of ["legacy_import_datasets","legacy_import_batches",
        "legacy_record_mappings","legacy_unresolved_records",
        "legacy_asset_journal","legacy_import_receipts"]){
      if(!names.has(required))throw new Error("WIZARD_V2_SCHEMA_REQUIRED");
    }
    const result=await runTrustedEvidenceWizard({
      selectedDirectory:source, canonicalDb:db,
      // ONLY local trusted console principal for this reference.
      // Product owner identity MUST come from authenticated Venera host.
      ownerScopeId:"local-console-uid:"+process.getuid(),
      datasetIntent:fields.has("--dataset-label")?"new":"existing",
      datasetId:fields.get("--dataset-id")??null,
      newDatasetLabel:fields.get("--dataset-label")??null,
      snapshotLeaseRegistry:new TrustedSnapshotLeaseRegistry(),
      gestureAuthority
    });
    process.stdout.write(JSON.stringify({
      status:result.status,scope:result.scope,
      importedContents:0,importedSettings:0,importedReaderPositions:0
    })+"\n");
  }catch(error){
    // Avoid paths, raw SQLite SQL, old titles, tokens and exception stacks.
    const accepted=new Set([
      "WIZARD_TRUSTED_TTY_REQUIRED","WIZARD_HOST_UNSUPPORTED",
      "WIZARD_SOURCE_INVALID","WIZARD_TARGET_INVALID",
      "WIZARD_V2_SCHEMA_REQUIRED","WIZARD_GESTURE_CANCELLED",
      "WIZARD_GESTURE_REJECTED","WIZARD_GESTURE_INVALID",
      "LEGACY_APPROVAL_STALE","LEGACY_APPROVAL_GESTURE_REJECTED"
    ]);
    failure(accepted.has(error?.code)?error.code:
      accepted.has(error?.message)?error.message:"WIZARD_FAILED");
  }finally{db?.close();}
}
