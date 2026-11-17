with CryptoLib.Hashes;

--  Streaming canonical name/value hashing for persistent semantic identities.
package Improve.Canonical_Digests is
   --  Boundary-safe SHA-256 construction shared by semantic identity producers.

   type Builder is limited private;
   --  Mutable streaming digest state consumed by Finish.

   procedure Initialize
     (Item                : out Builder;
      Domain              : String := "";
      Maximum_Value_Bytes : Natural := Natural'Last);
   --  Start a digest. Domain bytes are included verbatim before canonical fields.
   --  @param Item Builder to initialize.
   --  @param Domain Versioned domain-separation bytes.
   --  @param Maximum_Value_Bytes Maximum aggregate field-value bytes.

   procedure Add (Item : in out Builder; Name, Value : String);
   --  Add one length-delimited name/value field.
   --  @param Item Initialized builder.
   --  @param Name Stable field name.
   --  @param Value Field value bytes.

   function Finish (Item : in out Builder; Prefix : String := "sha256:") return String;
   --  Finalize the digest and render lowercase hexadecimal output.
   --  @param Item Initialized builder consumed by this call.
   --  @param Prefix Text prepended to the hexadecimal digest.
   --  @return Prefix followed by sixty-four lowercase hexadecimal digits.

private
   type Builder is limited record
      Context             : CryptoLib.Hashes.SHA256_Context;
      Maximum_Value_Bytes : Natural := Natural'Last;
      Used_Value_Bytes    : Natural := 0;
      Initialized         : Boolean := False;
   end record;
end Improve.Canonical_Digests;
