// Trusted-host proof reader: immutable revision, not current source order.
// This is not an app-integrated ContentUnit resolver.
import { createHash } from 'node:crypto';

const ID=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/;
const SHA=/^[0-9a-f]{64}$/;
function fail(code){const e=new Error(code);e.code=code;throw e;}
const hash=b=>createHash('sha256').update(b).digest('hex');

/**
 * Resolve ONE saved historical page. All metadata/byte authorities are held
 * by trusted host ports; a plugin must never supply "verified" placement
 * receipts or choose ownerScopeId.
 */
export async function readHistoricalPage({
  store,canonical,placements,ownerScopeId,snapshotId,ordinal
}={}) {
  if (![ownerScopeId,snapshotId].every(x=>typeof x==='string'&&ID.test(x))||
      !Number.isSafeInteger(ordinal)||ordinal<0||ordinal>127)fail('INVALID_HISTORICAL_READ');
  if(typeof store?.auditSnapshot!=='function'||
      typeof store?.readCommittedManifest!=='function'||
      typeof store?.readPreservedPage!=='function'||
      typeof canonical?.readPreservedVersion!=='function'||
      typeof placements?.verifyReadablePlacement!=='function')fail('TRUSTED_PORT_UNAVAILABLE');
  // Do not consult readSectionOrder() or any website-specific provider here.
  const committed=await canonical.readPreservedVersion({ownerScopeId,snapshotId});
  if(committed?.snapshotId!==snapshotId || !SHA.test(committed?.manifestSha256)||
      !Array.isArray(committed.pages)||committed.pages.length<1||
      committed.pages.length>128)fail('HISTORICAL_REFERENCE_INVALID');
  const audit=await store.auditSnapshot({snapshotId});
  if(audit?.status!=='healthy')fail('HISTORICAL_PROOF_UNHEALTHY');
  const envelope=await store.readCommittedManifest({snapshotId});
  const m=envelope?.manifest;
  if(envelope?.formatVersion!==1||envelope.manifestSha256!==committed.manifestSha256||
      !m||m.snapshotId!==snapshotId||m.contentId!==committed.contentId||
      m.sectionId!==committed.sectionId||hash(JSON.stringify(m))!==envelope.manifestSha256||
      !Array.isArray(m.pages)||m.pages.length!==committed.pages.length ||
      m.countEvidence!=='verified_source_count')fail('HISTORICAL_MANIFEST_MISMATCH');
  // Compare entire immutable ordering against authoritative saved edges,
  // NOT today's mutable unit order or a remote URL/page index.
  for(let index=0;index<committed.pages.length;index++){
    const row=committed.pages[index],page=m.pages[index];
    if(row?.ordinal!==index||page?.ordinal!==index||
      row.unitId!==page.unitId||row.storageObjectId!==page.storageObjectId||
      row.sha256!==page.sha256||row.byteLength!==page.byteLength||
      typeof row.placementId!=='string'||!ID.test(row.placementId))
      fail('HISTORICAL_BINDING_MISMATCH');
  }
  if(ordinal>=m.pages.length)fail('HISTORICAL_PAGE_NOT_FOUND');
  const page=m.pages[ordinal],row=committed.pages[ordinal];
  const bytesResult=await store.readPreservedPage({snapshotId,ordinal});
  if(bytesResult?.unitId!==page.unitId ||
      bytesResult.mimeType!==page.mimeType ||
      !(bytesResult.bytes instanceof Uint8Array) ||
      bytesResult.bytes.byteLength!==page.byteLength||
      hash(bytesResult.bytes)!==page.sha256)fail('HISTORICAL_BYTES_CORRUPT');
  const location=await placements.verifyReadablePlacement({
    ownerScopeId,storageObjectId:page.storageObjectId,
    expectedSha256:page.sha256,expectedBytes:page.byteLength
  });
  if(location?.verified!==true||location.ownerScopeId!==ownerScopeId||
      location.placementId!==row.placementId||
      location.storageObjectId!==page.storageObjectId||
      location.sha256!==page.sha256||location.byteLength!==page.byteLength||
      !['authority','mirror'].includes(location.role)||location.syncStatus!=='synced')
    fail('HISTORICAL_PLACEMENT_UNVERIFIED');
  return Object.freeze({
    origin:'preserved',snapshotId,unitId:page.unitId,ordinal,
    mimeType:page.mimeType,bytes:bytesResult.bytes
  });
}
