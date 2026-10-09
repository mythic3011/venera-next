// Trusted-host in-memory lease of bytes already obtained by an approved,
// OS-isolated and consistent source snapshotter. This module DOES NOT read
// arbitrary paths, run SQLite, attest records, or create UI permissions.
// Never expose the registry or buffers across plugin JS / renderer RPC.
import { createHash, randomUUID } from "node:crypto";
import { legacyRecordIdentity } from "./record-identity.mjs";

const ROLES = Object.freeze([
  "local.db", "history.db", "local_favorite.db", "appdata.json", "implicitData.json"
]);
const MAX = Object.freeze({
  "local.db": 48 * 1024 * 1024,
  "history.db": 48 * 1024 * 1024,
  "local_favorite.db": 48 * 1024 * 1024,
  "appdata.json": 4 * 1024 * 1024,
  "implicitData.json": 4 * 1024 * 1024
});
const MAX_TOTAL = 152 * 1024 * 1024;
const MAX_TTL_MS = 15 * 60 * 1000;
const DEFAULT_TTL_MS = 5 * 60 * 1000;
const MAX_EVIDENCE_RECORDS=100000;
const SHA256 = /^[0-9a-f]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export class SnapshotLeaseError extends Error {
  constructor(code) { super(code); this.name="SnapshotLeaseError"; this.code=code; }
}
function reject(code) { throw new SnapshotLeaseError(code); }
function stringId(s) {
  return typeof s==="string" && s.length>0 && s.length<=256 && !s.includes("\0");
}
function checkPayload(role, bytes) {
  if (role.endsWith(".db")) {
    if (bytes.length<16 || bytes.subarray(0,16).toString("binary")!=="SQLite format 3\0")
      reject("LEASE_FORMAT_REJECTED");
  } else {
    // Schema verification and exclusion of secrets is a separate isolated
    // parser gate; this only rejects non-JSON byte streams.
    try {
      const t = new TextDecoder("utf-8",{fatal:true}).decode(bytes);
      const data=JSON.parse(t);
      if (!data || typeof data!=="object" || Array.isArray(data))
        reject("LEASE_FORMAT_REJECTED");
    } catch { reject("LEASE_FORMAT_REJECTED"); }
  }
}
function digest(buffer) {return createHash("sha256").update(buffer).digest("hex");}
function compareManifest(stored, received) {
  return Array.isArray(received) && received.length===stored.length &&
    stored.every((r,i)=>received[i]?.role===r.role &&
      SHA256.test(received[i]?.sha256) && received[i].sha256===r.sha256 &&
      Object.keys(received[i]).sort().join(",")==="role,sha256");
}

function compileRecordEvidence(proofs, manifest, datasetId) {
  if(!Array.isArray(proofs) || proofs.length>1)
    reject("LEASE_EVIDENCE_INVALID");
  const map=new Map();
  for(const proof of proofs) {
    if(!proof || typeof proof!=="object" || Array.isArray(proof) ||
       Object.keys(proof).sort().join(",")!=="records,role,snapshotSha256,version" ||
       proof.version!==1 || proof.role!=="local.db" ||
       !Array.isArray(proof.records) || proof.records.length>MAX_EVIDENCE_RECORDS)
      reject("LEASE_EVIDENCE_INVALID");
    const matched=manifest.find(x=>x.role===proof.role);
    if(!matched || matched.sha256!==proof.snapshotSha256)
      reject("LEASE_EVIDENCE_SNAPSHOT_MISMATCH");
    for(const record of proof.records) {
      if(!record || typeof record!=="object" || Array.isArray(record) ||
         Object.keys(record).sort().join(",")!==
           "fileRole,legacyId,legacyTypeKey,recordDigest,scopeKey,tableKind" ||
         record.fileRole!=="local.db" || record.tableKind!=="comics" ||
         record.scopeKey!=="" || !SHA256.test(record.recordDigest))
        reject("LEASE_EVIDENCE_INVALID");
      let identity;
      try { identity=legacyRecordIdentity({datasetId,
        fileRole:record.fileRole,tableKind:record.tableKind,
        scopeKey:record.scopeKey,legacyTypeKey:record.legacyTypeKey,
        legacyId:record.legacyId}); }
      catch { reject("LEASE_EVIDENCE_INVALID"); }
      if(map.has(identity.keyDigest))reject("LEASE_EVIDENCE_DUPLICATE");
      map.set(identity.keyDigest,record.recordDigest);
    }
  }
  // If a local.db snapshot is present, evidence must be supplied and complete
  // by the *trusted isolated exporter*. Registry can't itself parse the DB.
  if(manifest.some(x=>x.role==="local.db") && proofs.length!==1)
    reject("LEASE_EVIDENCE_MISSING");
  return map;
}

export class TrustedSnapshotLeaseRegistry {
  #leases=new Map();
  #clock;
  constructor({now=()=>Date.now()}={}) {
    if(typeof now!=="function")reject("LEASE_CLOCK_INVALID");
    this.#clock=now;
  }
  #expire(ref, entry) {
    if(this.#clock() < entry.expiresAt)return false;
    this.#purge(ref,entry);
    return true;
  }
  #purge(ref,entry) {
    this.#leases.delete(ref);
    for(const buf of entry.buffers.values())buf.fill(0); // best effort; GC also applies
    entry.buffers.clear();
    entry.provenance.clear();
  }
  // inputs are Buffer copies from the trusted *already isolated* snapshotter,
  // not untrusted RPC values or bytes opened by the main UI process.
  issue({ownerScopeId,datasetId,inputs,recordProofs=[],ttlMs=DEFAULT_TTL_MS}) {
    if(!stringId(ownerScopeId) || !UUID.test(datasetId) ||
       !Number.isSafeInteger(ttlMs) || ttlMs<1 || ttlMs>MAX_TTL_MS ||
       !Array.isArray(inputs) || inputs.length<1 || inputs.length>ROLES.length)
      reject("LEASE_INPUT_INVALID");
    const seen=new Set(),bufferMap=new Map(),manifest=[],total={n:0};
    try {
      for(const input of inputs) {
        if(!input || typeof input!=="object" ||
            !ROLES.includes(input.role) || seen.has(input.role) ||
            !(Buffer.isBuffer(input.bytes) || input.bytes instanceof Uint8Array))
          reject("LEASE_INPUT_INVALID");
        seen.add(input.role);
        if(input.bytes.byteLength>MAX[input.role] || input.bytes.byteLength<2)
          reject("LEASE_BUDGET_EXCEEDED");
        total.n+=input.bytes.byteLength;
        if(total.n>MAX_TOTAL)reject("LEASE_BUDGET_EXCEEDED");
        const copied=Buffer.from(input.bytes);
        checkPayload(input.role,copied);
        bufferMap.set(input.role,copied);
        manifest.push({role:input.role,sha256:digest(copied)});
      }
      manifest.sort((a,b)=>ROLES.indexOf(a.role)-ROLES.indexOf(b.role));
      const provenance=compileRecordEvidence(recordProofs,manifest,datasetId);
      const leaseRef=randomUUID(),expiresAt=this.#clock()+ttlMs;
      const entry={ownerScopeId,datasetId,buffers:bufferMap,provenance,
        manifest:Object.freeze(manifest.map(e=>Object.freeze(e))),expiresAt};
      this.#leases.set(leaseRef,entry);
      return Object.freeze({leaseRef,expiresAt});
    } catch(err) {
      for(const b of bufferMap.values())b.fill(0);
      throw err;
    }
  }
  #get({leaseRef,ownerScopeId,datasetId}) {
    if(!UUID.test(leaseRef)||!stringId(ownerScopeId)||!UUID.test(datasetId))
      return null;
    const entry=this.#leases.get(leaseRef);
    if(!entry || this.#expire(leaseRef,entry) ||
       entry.ownerScopeId!==ownerScopeId || entry.datasetId!==datasetId)
      return null;
    return entry;
  }
  getManifest({leaseRef,ownerScopeId,datasetId}) {
    const e=this.#get({leaseRef,ownerScopeId,datasetId});
    if(!e)return null;
    return Object.freeze(e.manifest.map(x=>Object.freeze({...x})));
  }
  // Re-hash private immutable byte copies at approval time; never silently
  // reopen mutable user source paths, even if original DB changes after preview.
  verify({leaseRef,ownerScopeId,datasetId,inputManifest}) {
    const e=this.#get({leaseRef,ownerScopeId,datasetId});
    return !!e && compareManifest(e.manifest,inputManifest) &&
      e.manifest.every(({role,sha256})=>digest(e.buffers.get(role))===sha256);
  }
  // Provenance can only be checked for an identity and digest that were in
  // the approved, immutable snapshot's private per-record evidence index.
  verifyRecord({leaseRef,ownerScopeId,datasetId,inputManifest,key,recordDigest}) {
    if(!this.verify({leaseRef,ownerScopeId,datasetId,inputManifest}) ||
       !SHA256.test(recordDigest))return false;
    const e=this.#get({leaseRef,ownerScopeId,datasetId});
    let digestKey;
    try { digestKey=legacyRecordIdentity(key).keyDigest; }
    catch { return false; }
    return key.datasetId===datasetId && e.provenance.get(digestKey)===recordDigest;
  }
  revoke({leaseRef,ownerScopeId,datasetId}) {
    const e=this.#get({leaseRef,ownerScopeId,datasetId});
    if(!e)return false;
    this.#purge(leaseRef,e);
    return true;
  }
  purgeExpired() {
    let removed=0;
    for(const [ref,e] of this.#leases)
      if(this.#expire(ref,e))removed++;
    return removed;
  }
}
