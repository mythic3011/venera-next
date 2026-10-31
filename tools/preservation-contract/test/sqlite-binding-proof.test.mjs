import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createHash } from 'node:crypto';
import { publishPreservedSnapshot } from '../src/canonical-publish-gate.mjs';
import { fingerprintCanonicalOrder } from '../src/canonical-publish-gate.mjs';
import { createSqliteBindingProof } from '../src/sqlite-binding-proof.mjs';

// Test-only table subset, not a replacement for PR #6's canonical v2 schema.
const DDL = `
CREATE TABLE contents (id TEXT PRIMARY KEY,library_status TEXT NOT NULL);
CREATE TABLE content_sections (id TEXT PRIMARY KEY,content_id TEXT NOT NULL REFERENCES contents(id));
CREATE TABLE content_units (
  id TEXT PRIMARY KEY,section_id TEXT NOT NULL REFERENCES content_sections(id),
  unit_index INTEGER NOT NULL,UNIQUE(section_id,unit_index)
);
CREATE TABLE content_unit_orders (
  id TEXT PRIMARY KEY,section_id TEXT NOT NULL REFERENCES content_sections(id),status TEXT NOT NULL
);
CREATE TABLE content_unit_order_items (
  order_id TEXT NOT NULL REFERENCES content_unit_orders(id),unit_id TEXT NOT NULL REFERENCES content_units(id),
  sort_index INTEGER NOT NULL,UNIQUE(order_id,sort_index),UNIQUE(order_id,unit_id)
);
CREATE TABLE storage_objects (
  id TEXT PRIMARY KEY,object_kind TEXT NOT NULL,content_hash TEXT NOT NULL,size_bytes INTEGER NOT NULL
);
CREATE TABLE storage_placements (
  id TEXT PRIMARY KEY,storage_object_id TEXT NOT NULL REFERENCES storage_objects(id),
  role TEXT NOT NULL,sync_status TEXT NOT NULL
);
CREATE TABLE v2_storage_write_journal (
  planned_storage_id TEXT NOT NULL,planned_placement_id TEXT NOT NULL,owner_scope_id TEXT NOT NULL,
  state TEXT NOT NULL,authorization_scope TEXT NOT NULL,expected_sha256 TEXT NOT NULL,
  expected_bytes INTEGER NOT NULL
);
CREATE TABLE proof_content_owners (
  owner_scope_id TEXT NOT NULL,content_id TEXT NOT NULL REFERENCES contents(id),
  PRIMARY KEY(owner_scope_id,content_id)
);
CREATE TABLE proof_preservation_snapshots (
  id TEXT PRIMARY KEY,owner_scope_id TEXT NOT NULL,content_id TEXT NOT NULL REFERENCES contents(id),
  section_id TEXT NOT NULL REFERENCES content_sections(id),manifest_sha256 TEXT NOT NULL,
  order_digest TEXT NOT NULL,state TEXT NOT NULL,pinned INTEGER NOT NULL,created_at TEXT NOT NULL
);
CREATE TABLE proof_preservation_pages (
  snapshot_id TEXT NOT NULL REFERENCES proof_preservation_snapshots(id),
  ordinal INTEGER NOT NULL,unit_id TEXT NOT NULL REFERENCES content_units(id),
  storage_object_id TEXT NOT NULL REFERENCES storage_objects(id),
  placement_id TEXT NOT NULL REFERENCES storage_placements(id),
  sha256 TEXT NOT NULL,byte_length INTEGER NOT NULL,PRIMARY KEY(snapshot_id,ordinal)
);
`;

const DIGEST=['a'.repeat(64),'b'.repeat(64)];
function fixture(options={}) {
  const db=new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys=ON');
  db.exec(DDL);
  db.exec(`
  INSERT INTO contents VALUES ('work-1','active');
  INSERT INTO content_sections VALUES ('section-1','work-1');
  INSERT INTO content_units VALUES ('unit-1','section-1',7),('unit-2','section-1',15);
  INSERT INTO content_unit_orders VALUES ('order-1','section-1','active');
  INSERT INTO content_unit_order_items VALUES ('order-1','unit-1',0),('order-1','unit-2',1);
  INSERT INTO proof_content_owners VALUES ('owner-1','work-1');
  `);
  for(let i=0;i<2;i++){
    const id=i+1;
    db.prepare('INSERT INTO storage_objects VALUES (?,?,?,?)').run('object-'+id,'unit_image',DIGEST[i],9);
    db.prepare('INSERT INTO storage_placements VALUES (?,?,?,?)').run('place-'+id,'object-'+id,'authority','synced');
    db.prepare('INSERT INTO v2_storage_write_journal VALUES (?,?,?,?,?,?,?)')
      .run('object-'+id,'place-'+id,'owner-1','committed','storage_object_only',DIGEST[i],9);
  }
  const leased={active:options.leaseActive??true};
  const port=createSqliteBindingProof({
    db, assertActiveLease:()=>leased.active,
    checkpoint:options.checkpoint??(()=>{}),
  });
  const input={
    ownerScopeId:'owner-1',snapshotId:'snap-1',contentId:'work-1',
    sectionId:'section-1',manifestSha256:'f'.repeat(64),
    expectedOrderDigest:fingerprintCanonicalOrder({
      contentId:'work-1',sectionId:'section-1',
      units:[{id:'unit-1',unitIndex:7},{id:'unit-2',unitIndex:15}]
    }),
    links:[0,1].map(i=>({
      ordinal:i,unitId:'unit-'+(i+1),storageObjectId:'object-'+(i+1),
      placementId:'place-'+(i+1),sha256:DIGEST[i],byteLength:9,
    })),
  };
  return {db,port,input,leased};
}
async function withFixture(fn,opts) {
  const f=fixture(opts);
  try {await fn(f);}finally{f.db.close();}
}
function rows(db,table){return db.prepare('SELECT count(*) AS n FROM '+table).get().n;}

test('real SQLite BEGIN IMMEDIATE commit inserts version and page edges, not active unit bytes',()=>withFixture(({db,port,input})=>{
  assert.deepEqual(port.readSectionOrder(input).units,[
    {id:'unit-1',unitIndex:7},{id:'unit-2',unitIndex:15},
  ]);
  const result=port.commitPreservationBinding(input);
  assert.equal(result.state,'committed');
  assert.equal(rows(db,'proof_preservation_pages'),2);
  assert.equal(rows(db,'proof_preservation_snapshots'),1);
  assert.equal(db.prepare('SELECT pinned FROM proof_preservation_snapshots').get().pinned,1);
  assert.equal(db.prepare("SELECT count(*) AS n FROM content_units WHERE id='unit-1' AND unit_index=7").get().n,1);
}));

test('identical retry returns replay; different manifest for same snapshot ID conflicts',()=>withFixture(({db,port,input})=>{
  assert.equal(port.commitPreservationBinding(input).state,'committed');
  assert.equal(port.commitPreservationBinding(input).state,'replayed');
  assert.throws(()=>port.commitPreservationBinding({...input,manifestSha256:'c'.repeat(64)}),
    {code:'SNAPSHOT_ID_CONFLICT'});
  assert.equal(rows(db,'proof_preservation_snapshots'),1);
}));

test('active canonical order changed since preflight: reject without inserting snapshot',()=>withFixture(({db,port,input})=>{
  db.exec("UPDATE content_unit_order_items SET sort_index=2 WHERE unit_id='unit-1'");
  db.exec("UPDATE content_unit_order_items SET sort_index=0 WHERE unit_id='unit-2'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'ORDER_CHANGED_AT_COMMIT'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('missing unit and incomplete snapshot relation rejected',()=>withFixture(({db,port,input})=>{
  assert.throws(()=>port.commitPreservationBinding({...input,links:input.links.slice(0,1)}),
    {code:'INCOMPLETE_BINDING'});
  assert.throws(()=>port.commitPreservationBinding({...input,links:[
    {...input.links[0],unitId:'unit-2'},input.links[1],
  ]}),{code:'PAGE_BINDING_INVALID'});
  assert.equal(rows(db,'proof_preservation_pages'),0);
}));

test('cross-owner access rejected, even when attacker knows valid IDs',()=>withFixture(({db,port,input})=>{
  assert.throws(()=>port.commitPreservationBinding({...input,ownerScopeId:'owner-2'}),
    {code:'OWNER_SCOPE_DENIED'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('committed storage journal owner must match active content owner',()=>withFixture(({db,port,input})=>{
  db.exec("UPDATE v2_storage_write_journal SET owner_scope_id='owner-2' WHERE planned_storage_id='object-1'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'STORAGE_OWNER_OR_JOURNAL_INVALID'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('storage-only grant is not implicitly upgraded when journal pending',()=>withFixture(({db,port,input})=>{
  db.exec("UPDATE v2_storage_write_journal SET state='promoted' WHERE planned_storage_id='object-2'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'STORAGE_OWNER_OR_JOURNAL_INVALID'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('pending placement and cache role both rejected at commit',()=>withFixture(({db,port,input})=>{
  db.exec("UPDATE storage_placements SET sync_status='pending' WHERE id='place-2'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'PLACEMENT_CHANGED_AT_COMMIT'});
  db.exec("UPDATE storage_placements SET sync_status='synced',role='cache' WHERE id='place-2'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'PLACEMENT_CHANGED_AT_COMMIT'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('stale hash/size metadata rejected before any canonical mutation',()=>withFixture(({db,port,input})=>{
  db.exec("UPDATE storage_objects SET content_hash='not-the-file' WHERE id='object-1'");
  assert.throws(()=>port.commitPreservationBinding(input),{code:'PLACEMENT_CHANGED_AT_COMMIT'});
  assert.equal(rows(db,'proof_preservation_pages'),0);
}));

test('expired/revoked physical byte lease must fail closed',()=>withFixture(({db,port,input,leased})=>{
  leased.active=false;
  assert.throws(()=>port.commitPreservationBinding(input),{code:'PRESERVATION_LEASE_REVOKED'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('fault injected after first page insert rolls back entire SQLite transaction',()=>withFixture(({db,port,input})=>{
  assert.throws(()=>port.commitPreservationBinding(input),/simulated commit crash/);
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
  assert.equal(rows(db,'proof_preservation_pages'),0);
}, {checkpoint:({ordinal})=>{if(ordinal===0)throw Error('simulated commit crash');}}));

test('missing owner registry cannot act as permissive fallback',()=>withFixture(({db,port,input})=>{
  db.exec('DELETE FROM proof_content_owners');
  assert.throws(()=>port.readSectionOrder(input),{code:'OWNER_SCOPE_DENIED'});
  assert.throws(()=>port.commitPreservationBinding(input),{code:'OWNER_SCOPE_DENIED'});
}));

test('partial active order fails closed and does not silently use synthetic order',()=>withFixture(({db,port,input})=>{
  db.exec("DELETE FROM content_unit_order_items WHERE unit_id='unit-2'");
  assert.throws(()=>port.readSectionOrder(input),{code:'ACTIVE_ORDER_INVALID'});
  assert.throws(()=>port.commitPreservationBinding(input),{code:'ACTIVE_ORDER_INVALID'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));

test('active order absent allows gaps and source ordering but protects snapshot CAS',()=>withFixture(({db,port,input})=>{
  db.exec('DELETE FROM content_unit_order_items');
  db.exec('DELETE FROM content_unit_orders');
  assert.equal(port.commitPreservationBinding(input).state,'committed');
  assert.equal(rows(db,'proof_preservation_pages'),2);
}));

test('foreign keys are mandatory to prevent orphan preservation reference',()=>{
  const db=new DatabaseSync(':memory:');
  try {
    db.exec(DDL);
    assert.throws(()=>createSqliteBindingProof({db,assertActiveLease:()=>true}),
      {code:'FOREIGN_KEYS_REQUIRED'});
  } finally {db.close();}
});


// Proof store + host port + SQLite transaction, with in-memory byte evidence.
// Deliberately a fake source/placement lease, not live Linux / PR #6 storage.
function pipelineFixture(state) {
  const data=[Uint8Array.from([137,80,78,71,13,10,26,10,1]),
              Uint8Array.from([137,80,78,71,13,10,26,10,2])];
  const digests=data.map(b=>createHash('sha256').update(b).digest('hex'));
  for(let i=0;i<2;i++){
    state.db.prepare('UPDATE storage_objects SET content_hash=?,size_bytes=? WHERE id=?')
      .run(digests[i],data[i].length,'object-'+(i+1));
    state.db.prepare('UPDATE v2_storage_write_journal SET expected_sha256=?,expected_bytes=? WHERE planned_storage_id=?')
      .run(digests[i],data[i].length,'object-'+(i+1));
  }
  const manifest={
    schemaVersion:1,snapshotId:'snap-1',contentId:'work-1',sectionId:'section-1',
    countEvidence:'verified_source_count',expectedPageCount:2,
    pages:[0,1].map(i=>({ordinal:i,unitId:'unit-'+(i+1),
      storageObjectId:'object-'+(i+1),sha256:digests[i],byteLength:data[i].length,
      mimeType:'image/png'}))
  };
  const digest=x=>createHash('sha256').update(x).digest('hex');
  const wrapper={formatVersion:1,manifestSha256:digest(JSON.stringify(manifest)),manifest};
  const store={
    auditSnapshot:async()=>({status:'healthy'}),
    readCommittedManifest:async()=>wrapper,
    readPreservedPage:async({ordinal})=>({
      unitId:manifest.pages[ordinal].unitId,
      mimeType:'image/png',bytes:data[ordinal]
    }),
  };
  const placements={
    async verifyReadablePlacement({ownerScopeId,storageObjectId,expectedSha256,expectedBytes}){
      if(typeof state.onPlacement==='function')state.onPlacement();
      const n=storageObjectId.split('-').at(-1);
      return {verified:true,ownerScopeId,storageObjectId,
        placementId:'place-'+n,sha256:expectedSha256,byteLength:expectedBytes,
        role:'authority',syncStatus:'synced'};
    },
  };
  return {store,placements};
}
test('end-to-end fake proof-store -> publish gate -> real SQLite commit is visible',async()=>
  withFixture(async state=>{
    const {store,placements}=pipelineFixture(state);
    const r=await publishPreservedSnapshot({
      store,canonical:state.port,placements,ownerScopeId:'owner-1',snapshotId:'snap-1',
    });
    assert.equal(r.state,'committed');
    assert.equal(rows(state.db,'proof_preservation_snapshots'),1);
    assert.equal(rows(state.db,'proof_preservation_pages'),2);
  })
);
test('mutation between async preflight and SQLite BEGIN IMMEDIATE aborts binding',async()=>
  withFixture(async state=>{
    const {store,placements}=pipelineFixture(state);
    let changed=false;
    state.onPlacement=()=>{
      if(changed)return;
      changed=true;
      state.db.exec("UPDATE content_unit_order_items SET sort_index=3 WHERE unit_id='unit-1'");
      state.db.exec("UPDATE content_unit_order_items SET sort_index=0 WHERE unit_id='unit-2'");
    };
    await assert.rejects(publishPreservedSnapshot({
      store,canonical:state.port,placements,ownerScopeId:'owner-1',snapshotId:'snap-1',
    }),{code:'ORDER_CHANGED_AT_COMMIT'});
    assert.equal(rows(state.db,'proof_preservation_snapshots'),0);
  })
);

test('two active orders fail closed even if one happens to match source',()=>withFixture(({db,port,input})=>{
  db.exec("INSERT INTO content_unit_orders VALUES ('order-2','section-1','active')");
  assert.throws(()=>port.readSectionOrder(input),{code:'MULTIPLE_ACTIVE_ORDERS'});
  assert.throws(()=>port.commitPreservationBinding(input),{code:'MULTIPLE_ACTIVE_ORDERS'});
  assert.equal(rows(db,'proof_preservation_snapshots'),0);
}));
