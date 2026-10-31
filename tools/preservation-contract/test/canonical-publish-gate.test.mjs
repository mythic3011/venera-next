import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { openLocalPreservationProof } from '../src/durable-proof.mjs';
import { fingerprintCanonicalOrder, publishPreservedSnapshot } from '../src/canonical-publish-gate.mjs';

const bytes = n => Uint8Array.from([137,80,78,71,13,10,26,10,n]);
const capture = () => ({
  snapshotId:'snapshot-1',contentId:'content-1',sectionId:'section-1',
  capturedAt:'2026-10-31T13:00:00Z',expectedPageCount:2,
  countEvidence:'verified_source_count',
  pages:[
    {ordinal:0,unitId:'unit-1',storageObjectId:'object-1',mimeType:'image/png',bytes:bytes(1)},
    {ordinal:1,unitId:'unit-2',storageObjectId:'object-2',mimeType:'image/png',bytes:bytes(2)},
  ],
});
function canonicalFixture() {
  const units=[{id:'unit-1',unitIndex:7},{id:'unit-2',unitIndex:15}];
  let writes=0;
  const canonical={
    async readSectionOrder(){return {units:units.map(u=>({...u}))};},
    async commitPreservationBinding(command){
      const live=fingerprintCanonicalOrder({
        contentId:command.contentId,sectionId:command.sectionId,units,
      });
      if(live!==command.expectedOrderDigest){
        throw Object.assign(new Error('reordered'),{code:'CANONICAL_ORDER_CHANGED'});
      }
      writes++;
      return {state:'committed',snapshotId:command.snapshotId,manifestSha256:command.manifestSha256};
    },
  };
  return {units,canonical,getWrites:()=>writes};
}
function placementFixture() {
  return {
    async verifyReadablePlacement({storageObjectId,expectedSha256,expectedBytes}){
      return {verified:true,storageObjectId,sha256:expectedSha256,
        byteLength:expectedBytes,placementId:'placement-'+storageObjectId};
    },
  };
}
async function fixture(fn) {
  const root=await mkdtemp(join(tmpdir(),'venera-publication-'));
  await chmod(root,0o700);
  try {
    const store=await openLocalPreservationProof({privateRoot:root});
    try { await fn(store); } finally { await store.close(); }
  } finally { await rm(root,{recursive:true,force:true}); }
}

test('canonical publish requires verified complete disk snapshot and stable active unit order',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const {canonical,getWrites}=canonicalFixture();
  const receipt=await publishPreservedSnapshot({
    store,canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  });
  assert.equal(receipt.state,'committed');
  assert.equal(receipt.linkedPages,2);
  assert.equal(getWrites(),1);
}));
test('snapshot without committed manifest cannot publish a canonical reference',async()=>fixture(async store=>{
  const {canonical,getWrites}=canonicalFixture();
  await assert.rejects(publishPreservedSnapshot({
    store,canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'not-present'
  }),{code:'PRESERVATION_PROOF_UNHEALTHY'});
  assert.equal(getWrites(),0);
}));
test('reordered canonical units reject binding even with unchanged page bytes',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const state=canonicalFixture();state.units.reverse();
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  }),{code:'CANONICAL_PAGE_BINDING_MISMATCH'});
  assert.equal(state.getWrites(),0);
}));
test('active unitIndex gaps are valid and not assumed to equal ordinal',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const {canonical,getWrites}=canonicalFixture();
  await publishPreservedSnapshot({
    store,canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  });
  assert.equal(getWrites(),1);
}));
test('read-to-commit order race must be rejected atomically by trusted canonical port',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const state=canonicalFixture();
  const placements=placementFixture();
  const original=placements.verifyReadablePlacement.bind(placements);
  let seen=0;
  placements.verifyReadablePlacement=async arg=>{
    const proof=await original(arg);
    if(++seen===2) state.units.reverse();
    return proof;
  };
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,placements,ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  }),{code:'CANONICAL_ORDER_CHANGED'});
  assert.equal(state.getWrites(),0);
}));
test('unreadable or false placement proof fails before canonical mutation',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const state=canonicalFixture();
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,ownerScopeId:'owner-1',snapshotId:'snapshot-1',
    placements:{async verifyReadablePlacement(){return {verified:false};}},
  }),{code:'CANONICAL_PLACEMENT_UNVERIFIED'});
  assert.equal(state.getWrites(),0);
}));
test('wrong storage object or mismatched hash receipt is rejected',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const state=canonicalFixture();
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,ownerScopeId:'owner-1',snapshotId:'snapshot-1',
    placements:{async verifyReadablePlacement(arg){return {
      verified:true,placementId:'placement-1',storageObjectId:'other',
      sha256:arg.expectedSha256,byteLength:arg.expectedBytes,
    };}},
  }),{code:'CANONICAL_PLACEMENT_UNVERIFIED'});
  assert.equal(state.getWrites(),0);
}));
test('unconfirmed commit and mismatched commit receipt are not advertised as preserved',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  const state=canonicalFixture();
  state.canonical.commitPreservationBinding=async()=>({state:'pending'});
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  }),{code:'CANONICAL_COMMIT_UNCONFIRMED'});
  state.canonical.commitPreservationBinding=async()=>({
    state:'committed',snapshotId:'different',manifestSha256:'a'.repeat(64)
  });
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:state.canonical,placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  }),{code:'CANONICAL_COMMIT_RECEIPT_INVALID'});
}));
test('canonical port presence is mandatory (no direct DB or fake fallback)',async()=>fixture(async store=>{
  await store.writeCapture(capture());
  await assert.rejects(publishPreservedSnapshot({
    store,canonical:{},placements:placementFixture(),ownerScopeId:'owner-1',snapshotId:'snapshot-1'
  }),{code:'TRUSTED_PORT_UNAVAILABLE'});
}));
test('fingerprint uses display order rather than source unitIndex ordering',()=>{
  const base={contentId:'content-1',sectionId:'section-1',units:[
    {id:'unit-1',unitIndex:7},{id:'unit-2',unitIndex:15},
  ]};
  const original=fingerprintCanonicalOrder(base);
  const reordered=fingerprintCanonicalOrder({...base,units:[...base.units].reverse()});
  assert.notEqual(original,reordered);
  assert.throws(()=>fingerprintCanonicalOrder({...base,units:[
    {id:'unit-1',unitIndex:7},{id:'unit-1',unitIndex:15},
  ]}),{code:'CANONICAL_ORDER_INVALID'});
});
