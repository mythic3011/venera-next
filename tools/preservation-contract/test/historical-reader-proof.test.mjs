import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readHistoricalPage } from '../src/historical-reader-proof.mjs';

const sha=b=>createHash('sha256').update(b).digest('hex');
const bytes=Uint8Array.from([137,80,78,71,13,10,26,10,3]);
const manifest={
  schemaVersion:1,snapshotId:'snapshot-1',contentId:'work-1',
  sectionId:'section-1',countEvidence:'verified_source_count',expectedPageCount:1,
  pages:[{ordinal:0,unitId:'unit-1',storageObjectId:'object-1',mimeType:'image/png',
    byteLength:bytes.byteLength,sha256:sha(bytes)}]
};
const receipt={formatVersion:1,manifestSha256:sha(JSON.stringify(manifest)),manifest};
function fixture(override={}) {
  let sourceCalls=0;
  const record={
    snapshotId:'snapshot-1',contentId:'work-1',sectionId:'section-1',
    manifestSha256:receipt.manifestSha256,pages:[{
      ordinal:0,unitId:'unit-1',storageObjectId:'object-1',
      placementId:'place-1',byteLength:bytes.byteLength,sha256:sha(bytes)
    }]
  };
  const canonical={
    async readPreservedVersion({ownerScopeId,snapshotId}){
      if(ownerScopeId!=='owner-1' || snapshotId!=='snapshot-1')
        throw Object.assign(new Error('not found'),{code:'SNAPSHOT_UNAVAILABLE'});
      return override.record??record;
    },
    async readSectionOrder(){sourceCalls++;throw Error('must never query live order');}
  };
  const store={
    async auditSnapshot(){return {status:override.audit??'healthy'};},
    async readCommittedManifest(){return override.receipt??receipt;},
    async readPreservedPage(){return override.page??{
      unitId:'unit-1',mimeType:'image/png',bytes
    };},
  };
  const placements={
    async verifyReadablePlacement({ownerScopeId,storageObjectId,expectedSha256,expectedBytes}){
      return {verified:true,ownerScopeId,storageObjectId,
        placementId:override.placementId??'place-1',
        sha256:expectedSha256,byteLength:expectedBytes,
        role:'authority',syncStatus:override.syncStatus??'synced'};
    }
  };
  return {canonical,store,placements,sourceCalls:()=>sourceCalls};
}
const ask=(f,change={})=>readHistoricalPage({
  ...f,ownerScopeId:'owner-1',snapshotId:'snapshot-1',ordinal:0,...change
});

test('historical read succeeds without consulting current order or original source',async()=>{
  const f=fixture();
  const value=await ask(f);
  assert.equal(value.origin,'preserved');
  assert.equal(value.unitId,'unit-1');
  assert.deepEqual(value.bytes,bytes);
  assert.equal(f.sourceCalls(),0);
});
test('wrong owner cannot access historical data',async()=>{
  const f=fixture();
  await assert.rejects(ask(f,{ownerScopeId:'other'}),{code:'SNAPSHOT_UNAVAILABLE'});
});
test('corrupt committed proof cannot quietly fall back to live source',async()=>{
  const f=fixture({audit:'committed_bytes_unavailable'});
  await assert.rejects(ask(f),{code:'HISTORICAL_PROOF_UNHEALTHY'});
  assert.equal(f.sourceCalls(),0);
});
test('signed version digest mismatch fails even with plausible image bytes',async()=>{
  const f=fixture({receipt:{...receipt,manifestSha256:'f'.repeat(64)}});
  await assert.rejects(ask(f),{code:'HISTORICAL_MANIFEST_MISMATCH'});
});
test('stored historical link cannot silently rebind same ordinal to a new unit',async()=>{
  const f=fixture({record:{
    snapshotId:'snapshot-1',contentId:'work-1',sectionId:'section-1',
    manifestSha256:receipt.manifestSha256,pages:[{
      ordinal:0,unitId:'unit-2',storageObjectId:'object-1',
      placementId:'place-1',byteLength:bytes.byteLength,sha256:sha(bytes)
    }]
  }});
  await assert.rejects(ask(f),{code:'HISTORICAL_BINDING_MISMATCH'});
});
test('image corruption and wrong placement fail closed',async()=>{
  const broken=fixture({page:{unitId:'unit-1',mimeType:'image/png',bytes:Uint8Array.from([1,2])}});
  await assert.rejects(ask(broken),{code:'HISTORICAL_BYTES_CORRUPT'});
  const badPlacement=fixture({placementId:'place-2'});
  await assert.rejects(ask(badPlacement),{code:'HISTORICAL_PLACEMENT_UNVERIFIED'});
});
test('missing historical page cannot fetch page from current remote source',async()=>{
  const f=fixture();
  await assert.rejects(ask(f,{ordinal:1}),{code:'HISTORICAL_PAGE_NOT_FOUND'});
  assert.equal(f.sourceCalls(),0);
});
