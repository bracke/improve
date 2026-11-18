with Ada.Streams;
with CryptoLib.Ed25519;
with CryptoLib.Errors;
with Improve.Model;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;

package body Improve.Audit_Artifacts is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;
   use type Jsonlib.Errors.Error_Code;
   use type Ada.Streams.Stream_Element;

   procedure Add (Into : in out Unbounded_String; Value : String) is
   begin
      Append (Into, Natural'Image (Value'Length) & ":" & Value);
   end Add;

   function Canonical (Value : Improve.Results.Audit_Bundle) return String is
      Result : Unbounded_String;
      Plan   : Improve.Model.Plan_Revision renames Value.Plan;
   begin
      Add (Result, To_String (Plan.Plan_Id));
      Add (Result, Positive'Image (Plan.Revision));
      Add (Result, Improve.Model.Plan_Content_Fingerprint (Plan));
      Add (Result, Boolean'Image (Value.Approved));
      for Item of Value.History.Publications loop
         Add (Result, To_String (Item.Improve_Task_Id));
         Add (Result, To_String (Item.Harness_Task_Id));
         Add (Result, To_String (Item.Origin));
         Add (Result, To_String (Item.Contract));
         Add (Result, To_String (Item.State));
         Add (Result, Positive'Image (Item.Plan_Revision));
      end loop;
      for Item of Value.History.Verifications loop
         Add (Result, Improve.Model.Image (Item.Scope));
         Add (Result, To_String (Item.Task_Id));
         Add (Result, Positive'Image (Item.Plan_Revision));
         Add (Result, To_String (Item.Contract_Fingerprint));
         Add (Result, Positive'Image (Item.Assessment_Id));
         Add (Result, Improve.Model.Image (Item.Outcome));
         Add (Result, Boolean'Image (Item.Comparable));
         Add (Result, To_String (Item.Explanation));
      end loop;
      return To_String (Result);
   end Canonical;

   function Digest (Value : Improve.Results.Audit_Bundle) return String is
     (Improve.Stable_Digest (Canonical (Value)));

   function Nibble (C : Character) return Ada.Streams.Stream_Element is
   begin
      if C in '0' .. '9' then return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then return Character'Pos (C) - Character'Pos ('A') + 10;
      else raise Improve.Argument_Error with "signing key is not hexadecimal";
      end if;
   end Nibble;

   function Decode (Text : String; Bytes : Positive) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Bytes));
   begin
      if Text'Length /= Bytes * 2 then
         raise Improve.Argument_Error with "signing key must contain 64 hexadecimal characters";
      end if;
      for I in Result'Range loop
         declare P : constant Positive := Text'First + 2 * (Natural (I) - 1); begin
            Result (I) := 16 * Nibble (Text (P)) + Nibble (Text (P + 1));
         end;
      end loop;
      return Result;
   end Decode;

   function Encode (Value : Ada.Streams.Stream_Element_Array) return String is
      Hex    : constant String := "0123456789abcdef";
      Result : String (1 .. Value'Length * 2);
      P      : Positive := 1;
   begin
      for B of Value loop
         Result (P) := Hex (Natural (B / 16) + 1);
         Result (P + 1) := Hex (Natural (B mod 16) + 1);
         P := P + 2;
      end loop;
      return Result;
   end Encode;

   function Message (Text : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for I in Text'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Text'First + 1)) := Character'Pos (Text (I));
      end loop;
      return Result;
   end Message;

   procedure Sign
     (Bundle_Digest : String;
      Seed_Hex      : String;
      Public_Key    : out Unbounded_String;
      Signature     : out Unbounded_String) is
      use type CryptoLib.Errors.Status;
      Seed : constant Ada.Streams.Stream_Element_Array := Decode (Seed_Hex, 32);
      Pub  : Ada.Streams.Stream_Element_Array (1 .. 32);
      Sig  : Ada.Streams.Stream_Element_Array (1 .. 64);
   begin
      if CryptoLib.Ed25519.Public_Key_From_Seed (Seed, Pub) /= CryptoLib.Errors.Ok or else
        CryptoLib.Ed25519.Sign (Seed, Pub, Message (Bundle_Digest), Sig) /= CryptoLib.Errors.Ok
      then
         raise Improve.Data_Error with "Ed25519 audit signing failed";
      end if;
      Public_Key := To_Unbounded_String (Encode (Pub));
      Signature := To_Unbounded_String (Encode (Sig));
   end Sign;

   procedure Verify (Text : String) is
      Doc   : Document;
      Error : Jsonlib.Errors.Error_Info;
   begin
      Jsonlib.Parsers.Parse
        (Text, Doc, Error,
         (Max_Depth => 64, Max_Length => 16 * 1_024 * 1_024,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Error.Code /= Jsonlib.Errors.No_Error or else Kind (Doc, Root (Doc)) /= Object_Value then
         raise Improve.Data_Error with "audit document is not valid JSON";
      end if;
      declare
         Data    : constant Node := Member (Doc, Root (Doc), "data");
         Payload : constant Node := (if Is_Present (Data) then Member (Doc, Data, "canonical_payload") else No_Node);
         Hash    : constant Node := (if Is_Present (Data) then Member (Doc, Data, "bundle_digest") else No_Node);
      begin
         if not Is_Present (Payload) or else not Is_Present (Hash) or else
           Kind (Doc, Payload) /= String_Value or else Kind (Doc, Hash) /= String_Value
         then
            raise Improve.Data_Error with "audit document has no canonical payload and bundle digest";
         elsif Improve.Stable_Digest (As_String (Doc, Payload)) /= As_String (Doc, Hash) then
            raise Improve.Data_Error with "audit bundle digest mismatch";
         end if;
         if Has_Member (Doc, Data, "signature") or else Has_Member (Doc, Data, "public_key") then
            if not Has_Member (Doc, Data, "signature") or else not Has_Member (Doc, Data, "public_key") then
               raise Improve.Data_Error with "audit signature and public key must appear together";
            end if;
            declare
               use type CryptoLib.Errors.Status;
               Pub : constant Ada.Streams.Stream_Element_Array :=
                 Decode (As_String (Doc, Member (Doc, Data, "public_key")), 32);
               Sig : constant Ada.Streams.Stream_Element_Array :=
                 Decode (As_String (Doc, Member (Doc, Data, "signature")), 64);
            begin
               if CryptoLib.Ed25519.Verify (Pub, Sig, Message (As_String (Doc, Hash))) /= CryptoLib.Errors.Ok then
                  raise Improve.Data_Error with "audit Ed25519 signature mismatch";
               end if;
            end;
         end if;
      end;
   exception
      when Improve.Data_Error => raise;
      when others => raise Improve.Data_Error with "audit document integrity fields are malformed";
   end Verify;
end Improve.Audit_Artifacts;
