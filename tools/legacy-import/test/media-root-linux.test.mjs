import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp,mkdir,writeFile,symlink,rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { TrustedLinuxMediaRootGrants, MediaGrantError } from "../media-root-linux.mjs";

const DS="b7a7c16b-5045-4a4f-a61d-205724750911",OWNER="venera-owner";
const PNG=Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),Buffer.from("TEST IMAGE BYTES")]);
async function fixture(t) {
  const root=await mkdtemp(join(tmpdir(),"venera-media-grant-"));
  t.after(async()=>rm(root,{recursive:true,force:true}));
  await mkdir(join(root,"chapters"));
  await writeFile(join(root,"chapters","page01.png"),PNG);
  return root;
}
async function grant(registry,root,overrides={}) {
  return registry.grantFromTrustedPicker({
    ownerScopeId:OWNER,datasetId:DS,
    requestTrustedDirectory:async()=>root,...overrides
  });
}
function read(registry,ref,segments=["chapters","page01.png"],more={}) {
  return registry.readImage({
    grant:ref,ownerScopeId:OWNER,datasetId:DS,relativeSegments:segments,...more
  });
}
function denied(fn,code) {
  return assert.rejects(fn,e=>e instanceof MediaGrantError&&e.code===code);
}
test("trusted directory grant reads only rooted validated image bytes",async t=>{
  const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
  const ref=await grant(registry,root);
  assert.equal(JSON.stringify(ref),"{}"); // no serializable capability
  const result=await read(registry,ref);
  assert.equal(result.mimeType,"image/png");
  assert.equal(result.sizeBytes,PNG.length);
  assert.equal(result.sha256,createHash("sha256").update(PNG).digest("hex"));
  assert.deepEqual(result.bytes,PNG);
  await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
  await denied(()=>read(registry,ref),"MEDIA_SCOPE_DENIED");
});
test("absolute old database paths, traversal, slash and exotic separators are denied",async t=>{
  const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
  const ref=await grant(registry,root);
  for(const parts of [
    ["/etc/passwd"],["..","private.png"],[".","page01.png"],["chapters/../private.png"],
    ["chapters","..","page01.png"],["chapters","sub\\page.png"],[]
  ])await denied(()=>read(registry,ref,parts),"MEDIA_RELATIVE_PATH_INVALID");
  await denied(()=>read(registry,ref,["chapters","foo.svg"]),"MEDIA_UNSUPPORTED_FILE");
  await denied(()=>read(registry,ref,["chapters","page01.png","extra.png"]),"MEDIA_READ_DENIED");
  await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
});
test("symlink inside approved root is denied even if it points at a valid image",async t=>{
 const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
 const other=await mkdtemp(join(tmpdir(),"venera-media-outside-"));
 t.after(async()=>rm(other,{recursive:true,force:true}));
 await mkdir(join(other,"private"));
 await writeFile(join(other,"private","secret.png"),PNG);
 await symlink(other,join(root,"jump"));
 await symlink(join(other,"private","secret.png"),join(root,"chapters","fake.png"));
 const ref=await grant(registry,root);
 await denied(()=>read(registry,ref,["jump","private","secret.png"]),"MEDIA_READ_DENIED");
 await denied(()=>read(registry,ref,["chapters","fake.png"]),"MEDIA_READ_DENIED");
 await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
});
test("rejects direct file root, symlinked selected root and cancelled picker",async t=>{
 const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
 const link=join(root,"rootlink");
 await symlink(join(root,"chapters"),link);
 await denied(()=>grant(registry,link),"MEDIA_ROOT_UNAVAILABLE");
 await denied(()=>grant(registry,join(root,"chapters","page01.png")),"MEDIA_ROOT_UNAVAILABLE");
 await denied(()=>grant(registry,root,{requestTrustedDirectory:async()=>{
   throw new Error("cancel");
 }}),"MEDIA_GRANT_CANCELLED");
});
test("rejects wrong owner/dataset and does not leak roots",async t=>{
 const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
 const ref=await grant(registry,root);
 await denied(()=>read(registry,ref,undefined,{ownerScopeId:"cross-user"}),"MEDIA_SCOPE_DENIED");
 await denied(()=>read(registry,ref,undefined,{
   datasetId:"a1b2c3d4-badd-4bad-8bad-a1b2c3d4e5f6"}),"MEDIA_SCOPE_DENIED");
 assert.equal(JSON.stringify(ref).includes(root),false);
 await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
});
test("media extension must match content signature; non-media bytes rejected",async t=>{
 const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
 await writeFile(join(root,"chapters","payload.jpg"),PNG);
 await writeFile(join(root,"chapters","not-media.png"),Buffer.from("hello world"));
 const ref=await grant(registry,root);
 await denied(()=>read(registry,ref,["chapters","payload.jpg"]),"MEDIA_EXTENSION_MISMATCH");
 await denied(()=>read(registry,ref,["chapters","not-media.png"]),"MEDIA_MAGIC_INVALID");
 await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
});
test("grant expiry fails closed, and independent grant capacity is bounded",async t=>{
 const root=await fixture(t),registry=new TrustedLinuxMediaRootGrants();
 const refs=[];
 for(let i=0;i<4;i++)refs.push(await grant(registry,root));
 await denied(()=>grant(registry,root),"MEDIA_GRANT_CAPACITY");
 for(const ref of refs)await registry.revoke({grant:ref,ownerScopeId:OWNER,datasetId:DS});
 const ephemeral=await grant(registry,root,{ttlMs:25});
 await new Promise(resolve=>setTimeout(resolve,70));
 await denied(()=>read(registry,ephemeral),"MEDIA_SCOPE_DENIED");
});
