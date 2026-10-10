// Host-only, one-shot gesture verifier. No IPC, plugin or browser renderer API.
// A prompt adapter must be controlled by the TRUSTED host (TTY for this MVP).
import { randomBytes, timingSafeEqual } from "node:crypto";
import { createInterface } from "node:readline/promises";

export class WizardGestureError extends Error {
  constructor(code) { super(code); this.name="WizardGestureError"; this.code=code; }
}
function fail(code) { throw new WizardGestureError(code); }
const HEX64=/^[a-f0-9]{64}$/;
const MAX_AGE_MS=60_000;
function validContext(ctx) {
  return ctx && typeof ctx==="object" &&
    typeof ctx.ownerScopeId==="string" && ctx.ownerScopeId.length>0 &&
    typeof ctx.datasetId==="string" && ctx.datasetId.length>0 &&
    HEX64.test(ctx.planDigest);
}
function eq(a,b) {
  const left=Buffer.from(a,"utf8"),right=Buffer.from(b,"utf8");
  return left.length===right.length && timingSafeEqual(left,right);
}
export function createHostGestureAuthority({requestConfirmation,now=()=>Date.now()}) {
  if(typeof requestConfirmation!=="function" || typeof now!=="function")
    fail("WIZARD_TRUSTED_PROMPT_REQUIRED");
  const issued=new WeakMap();
  let pending=false;
  return Object.freeze({
    async confirm(context,preview) {
      if(!validContext(context) || pending)fail("WIZARD_GESTURE_INVALID");
      pending=true;
      const challenge="APPROVE "+context.planDigest.slice(0,10)+
        " "+randomBytes(6).toString("hex").toUpperCase();
      const createdAt=now();
      try {
        // The host UI owns challenge display and captures input.
        // No renderer-provided boolean or reusable approval token.
        let typed;
        try { typed=await requestConfirmation({challenge,context:Object.freeze({...context}),preview}); }
        catch { fail("WIZARD_GESTURE_CANCELLED"); }
        if(typeof typed!=="string" || typed.length>256 || now()-createdAt<0 ||
           now()-createdAt>MAX_AGE_MS || !eq(typed.trim(),challenge))
          fail("WIZARD_GESTURE_REJECTED");
        const gesture=Object.freeze(Object.create(null));
        issued.set(gesture,{...context,at:now()});
        return gesture;
      }finally{pending=false;}
    },
    async verifyTrustedUserGesture(gesture,context) {
      if(!validContext(context) || !gesture || typeof gesture!=="object")
        return false;
      const original=issued.get(gesture);
      if(!original)return false;
      issued.delete(gesture); // one-shot EVEN if wrong context or expired
      return now()-original.at>=0 && now()-original.at<=MAX_AGE_MS &&
        original.ownerScopeId===context.ownerScopeId &&
        original.datasetId===context.datasetId &&
        original.planDigest===context.planDigest;
    }
  });
}

// Local interactive terminal reference only. NOT Desktop UI, hardware-attested
// physical presence, OS identity authentication or a plugin/browser API.
export function createTTYGestureAuthority({
  input=process.stdin,output=process.stdout
}={}) {
  if(input!==process.stdin || output!==process.stdout ||
     !input.isTTY || !output.isTTY)fail("WIZARD_TRUSTED_TTY_REQUIRED");
  return createHostGestureAuthority({
    requestConfirmation:async ({challenge,preview})=>{
      output.write("\nOld Venera — metadata evidence approval ONLY.\n");
      output.write("NO comics/images/settings/reading position will be imported.\n");
      for(const file of preview.files)
        output.write(file.role+": "+file.status+
          " | records="+(file.records??0)+
          " | deferred="+(file.deferred??0)+
          " | review="+(file.reviewRequired??0)+"\n");
      output.write("To approve the exact pinned Snapshot, type the phrase:\n"+
        challenge+"\n");
      const rl=createInterface({input,output,terminal:true});
      try { return await rl.question("Confirmation (empty to cancel): "); }
      finally { rl.close(); }
    }
  });
}
