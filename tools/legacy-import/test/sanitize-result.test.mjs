import test from "node:test";
import assert from "node:assert/strict";
import { sanitizeSandboxResult } from "../sanitize-result.mjs";
const ROLES=["local.db","history.db","local_favorite.db","appdata.json","implicitData.json"];
function empty() {
 return {status:"no_inputs",scope:"old-venera-five-distributed-files",
  readOnly:true,canCommit:false,phase:"L0",
  files:ROLES.map(role=>({role,status:"missing",code:"SKIPPED_MISSING_INPUT"})),
  totals:{inspected:0,missing:5,rejected:0,records:0,eligible:0,
          deferred:0,reviewRequired:0,invalid:0}};
}
test("host output broker projects exact allowlisted statistics",()=>{
 const x=sanitizeSandboxResult(empty());
 assert.equal(x.status,"no_inputs");assert.equal(x.files.length,5);
 assert.ok(Object.isFrozen(x.files[0]));
});
test("unexpected private title, link, extra root or plan digest is denied",()=>{
 for(const variant of [
  x=>x.files[0].title="PRIVATE_USER_DATA",
  x=>x.files[1].auth="cookie",
  x=>x.planDigest="unsafe-private-identifier",
  x=>x.files[0].code="secret-as-error",
  x=>x.totals.extra="unexpected"
 ]){const x=empty();variant(x);assert.throws(()=>sanitizeSandboxResult(x),/SANDBOX_RESULT_INVALID/);}
});
test("forged counts, statuses and roles are rejected before reaching UI",()=>{
 for(const variant of [
  x=>x.totals.records=1,
  x=>x.totals.inspected=1,
  x=>x.files[0].role="venera.db",
  x=>x.status="preview_only",
  x=>x.files[0].status="verified",
  x=>x.readOnly=false,
  x=>x.canCommit=true
 ]){const x=empty();variant(x);assert.throws(()=>sanitizeSandboxResult(x),/SANDBOX_RESULT_INVALID/);}
});
