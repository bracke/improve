with Improve.Results;
with Ada.Strings.Unbounded;

--  Canonical integrity representation for exported audit evidence.
package Improve.Audit_Artifacts is
   --  Canonical hashing, optional signing, and verification of audit exports.

   function Canonical (Value : Improve.Results.Audit_Bundle) return String;
   --  Return a length-delimited representation of every audit-relevant field.
   --  @param Value Audit bundle to encode.
   --  @return Canonical length-delimited payload.

   function Digest (Value : Improve.Results.Audit_Bundle) return String;
   --  Return the SHA-256 digest of Canonical (Value).
   --  @param Value Audit bundle to identify.
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

   procedure Verify (Text : String);
   --  Verify the canonical payload and digest in an exported audit JSON document.
   --  @param Text Complete exported audit JSON document.
   --  @exception Improve.Data_Error The document is malformed or its digest does not match.
end Improve.Audit_Artifacts;
