with Ada.Strings.Unbounded;
with Jsonlib.Documents;

--  Canonical integrity representation for exported audit evidence.
package Improve.Audit_Artifacts is
   --  Canonical hashing, optional signing, and verification of audit exports.

   Maximum_Artifact_Bytes : constant Positive := 16 * 1_024 * 1_024;
   --  Maximum encoded size accepted for both generated and verified artifacts.

   type Verification_Mode is (Digest_Only, Trusted_Signature);
   --  Strength of the completed audit-artifact verification.
   --  @enum Digest_Only Canonical payload and digest verified without a signature.
   --  @enum Trusted_Signature Signature verified against an independently trusted public key.

   function Canonical_Data
     (Doc  : Jsonlib.Documents.Document;
      Data : Jsonlib.Documents.Node) return String;
   --  Serialize audit data with deterministic member ordering.
   --  @param Doc Document containing Data.
   --  @param Data Audit evidence object without integrity fields.
   --  @return Canonical compact JSON payload.

   function Digest (Canonical_Payload : String) return String;
   --  Return the SHA-256 digest of one canonical audit payload.
   --  @param Canonical_Payload Canonical JSON returned by Canonical_Data.
   --  @return Stable SHA-256 bundle digest.

   procedure Sign
     (Bundle_Digest : String;
      Seed_Hex      : String;
      Public_Key    : out Ada.Strings.Unbounded.Unbounded_String;
      Signature     : out Ada.Strings.Unbounded.Unbounded_String);
   --  Produce an Ed25519 signature and public key, both lowercase hexadecimal.
   --  @param Bundle_Digest Canonical bundle digest to sign.
   --  @param Seed_Hex Private Ed25519 seed as 64 hexadecimal characters.
   --  @param Public_Key Derived public key as lowercase hexadecimal.
   --  @param Signature Signature as lowercase hexadecimal.

   function Verify
     (Text               : String;
      Trusted_Public_Key : String := "") return Verification_Mode;
   --  Verify the canonical payload, digest, and any independently trusted signature.
   --  @param Text Complete exported audit JSON document.
   --  @param Trusted_Public_Key Expected Ed25519 public key as 64 hexadecimal characters.
   --  @return Digest_Only for an unsigned document or Trusted_Signature for a trusted signature.
   --  @exception Improve.Argument_Error A signed document has no trusted key or the trusted key is malformed.
   --  @exception Improve.Data_Error The document is malformed or its digest does not match.
end Improve.Audit_Artifacts;
