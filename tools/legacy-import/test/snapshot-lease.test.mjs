import test from "node:test";
import assert from "node:assert/strict";
import { TrustedSnapshotLeaseRegistry, SnapshotLeaseError } from "../snapshot-lease.mjs";

const OWNER="user-A";
const DATASET="54e20f34-2365-4bb9-a9ac-2e6b6fb48525";
const OTHER="39180d83-0a9d-4757-b630-6ed9af80a36d";
function dbbytes(extra="old") { return Buffer.from("SQLite format 3\0"+extra); }
function issue(registry, overrides={}) {
 return registry.issue({ownerScopeId:OWNER,datasetId:DATASET,
   inputs:[{role:"local.db",bytes:dbbytes()},{role:"appdata.json",bytes:Buffer.from('{"settings":{}}')}],
   ...overrides});
}
function context(leaseRef, extra={}) {
 return {leaseRef,ownerScopeId:OWNER,datasetId:DATASET,...extra};
}
test("lease is immutable under caller input buffer mutations",()=>{
 const r=new TrustedSnapshotLeaseRegistry();
 const external=dbbytes();
 const lease=issue(r,{inputs:[{role:"local.db",bytes:external}]});
 const initial=r.getManifest(context(lease.leaseRef));
 assert.equal(initial.length,1);
 external.fill(0);
 assert.equal(r.verify({...context(lease.leaseRef),inputManifest:initial}),true);
 assert.ok(Object.isFrozen(initial));
 assert.ok(Object.isFrozen(initial[0]));
});
test("owner, dataset, hash and role order are all bound",()=>{
 const r=new TrustedSnapshotLeaseRegistry();
 const l=issue(r);
 const m=r.getManifest(context(l.leaseRef));
 assert.deepEqual(m.map(x=>x.role),["local.db","appdata.json"]);
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:m}),true);
 assert.equal(r.verify({...context(l.leaseRef,{ownerScopeId:"user-B"}),inputManifest:m}),false);
 assert.equal(r.verify({...context(l.leaseRef,{datasetId:OTHER}),inputManifest:m}),false);
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:m.slice().reverse()}),false);
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:[{...m[0],sha256:"0".repeat(64)},m[1]]}),false);
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:m.map(x=>({...x,path:"secret"}))}),false);
});
test("expiry and revocation deny already-created leases",()=>{
 let now=1000;
 const r=new TrustedSnapshotLeaseRegistry({now:()=>now});
 const l=issue(r,{ttlMs:10});
 const m=r.getManifest(context(l.leaseRef));
 now=1009;
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:m}),true);
 now=1010;
 assert.equal(r.verify({...context(l.leaseRef),inputManifest:m}),false);
 assert.equal(r.getManifest(context(l.leaseRef)),null);
 const second=issue(r,{ttlMs:100});
 assert.equal(r.revoke(context(second.leaseRef,{ownerScopeId:"other"})),false);
 assert.equal(r.revoke(context(second.leaseRef)),true);
 assert.equal(r.revoke(context(second.leaseRef)),false);
});
test("five-file whitelist, duplicate role, malformed DB/JSON are rejected",()=>{
 const r=new TrustedSnapshotLeaseRegistry();
 for(const inputs of [
   [{role:"venera.db",bytes:dbbytes()}],
   [{role:"local.db",bytes:dbbytes()},{role:"local.db",bytes:dbbytes()}],
   [{role:"local.db",bytes:Buffer.from("not sqlite")}],
   [{role:"implicitData.json",bytes:Buffer.from("not json")}],
   [{role:"appdata.json",bytes:Buffer.from("[1]")}],
   [{role:"local.db",bytes:"untrusted string"}]
 ]) assert.throws(()=>issue(r,{inputs}),SnapshotLeaseError);
});
test("strict per-file budgets and short TTL are enforced",()=>{
 const r=new TrustedSnapshotLeaseRegistry();
 for(const ttlMs of [0,-1,900001,1.5])
   assert.throws(()=>issue(r,{ttlMs}),SnapshotLeaseError);
 assert.throws(()=>issue(r,{inputs:[{role:"appdata.json",
   bytes:Buffer.alloc(4*1024*1024+1,0x7b)}]}),SnapshotLeaseError);
});
test("one lease has no automatically persisted approval or canonical mapping",()=>{
 const r=new TrustedSnapshotLeaseRegistry();
 const l=issue(r);
 assert.deepEqual(Object.keys(l).sort(),["expiresAt","leaseRef"]);
 assert.equal("bytes" in l,false);
 assert.equal("inputManifest" in l,false);
 assert.equal("planDigest" in l,false);
});
