with Ada.Streams;
with CryptoLib.Ed25519;
with CryptoLib.Errors;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;

package body Improve.Audit_Artifacts is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;
   use type Jsonlib.Errors.Error_Code;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Array;

   function Canonical_Data
     (Doc  : Jsonlib.Documents.Document;
      Data : Jsonlib.Documents.Node) return String is
     (Jsonlib.Serializers.To_String
        (Doc, Data,
         (Form => Jsonlib.Serializers.Compact, Indent => 2,
          Escape_Non_Ascii => False, Sort_Members => True)));

   function Digest (Canonical_Payload : String) return String is
     (Improve.Stable_Digest (Canonical_Payload));

   function Nibble (C : Character) return Ada.Streams.Stream_Element is
   begin
      if C in '0' .. '9' then return Character'Pos (C) - Character'Pos ('0');
      elsif C in 'a' .. 'f' then return Character'Pos (C) - Character'Pos ('a') + 10;
      elsif C in 'A' .. 'F' then return Character'Pos (C) - Character'Pos ('A') + 10;
      else raise Improve.Argument_Error with "signing key is not hexadecimal";
      end if;
   end Nibble;

   function Decode
     (Text : String;
      Bytes : Positive;
      Name : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Bytes));
   begin
      if Text'Length /= Bytes * 2 then
         raise Improve.Argument_Error with
           Name & " must contain" & Natural'Image (Bytes * 2) & " hexadecimal characters";
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
      Seed : constant Ada.Streams.Stream_Element_Array := Decode (Seed_Hex, 32, "signing key");
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

   procedure Validate_Audit_Contract (Doc : Document; Data : Node) is
      procedure Require_Kind
        (Item     : Node;
         Expected : Value_Kind;
         Context  : String) is
      begin
         if not Is_Present (Item) or else Kind (Doc, Item) /= Expected then
            raise Improve.Data_Error with "audit " & Context & " has an invalid type";
         end if;
      end Require_Kind;

      procedure Require_Member
        (Object   : Node;
         Name     : String;
         Expected : Value_Kind) is
      begin
         Require_Kind (Member (Doc, Object, Name), Expected, Name);
      end Require_Member;

      procedure Require_Positive (Object : Node; Name : String) is
         Item : constant Node := Member (Doc, Object, Name);
      begin
         Require_Kind (Item, Integer_Value, Name);
         if As_Integer (Doc, Item) <= 0 then
            raise Improve.Data_Error with "audit " & Name & " must be positive";
         end if;
      end Require_Positive;

      procedure Require_String_Array (Object : Node; Name : String) is
         Items : constant Node := Member (Doc, Object, Name);
      begin
         Require_Kind (Items, Array_Value, Name);
         for Index in 1 .. Length (Doc, Items) loop
            Require_Kind (Element (Doc, Items, Index), String_Value, Name & " item");
         end loop;
      end Require_String_Array;

      procedure Require_Optional_SHA256 (Object : Node; Name : String) is
         Item  : constant Node := Member (Doc, Object, Name);
      begin
         Require_Kind (Item, String_Value, Name);
         declare
            Value : constant String := As_String (Doc, Item);
         begin
            if Value /= "" and then
              (Value'Length /= 64 or else
               (for some Character_Of_Value of Value => Character_Of_Value not in '0' .. '9' | 'a' .. 'f'))
            then
               raise Improve.Data_Error with
                 "audit " & Name & " must be empty or 64 lower-case hexadecimal characters";
            end if;
         end;
      end Require_Optional_SHA256;

      procedure Validate_Tasks is
         Items : constant Node := Member (Doc, Data, "tasks");
      begin
         Require_Kind (Items, Array_Value, "tasks");
         for Index in 1 .. Length (Doc, Items) loop
            declare
               Item : constant Node := Element (Doc, Items, Index);
            begin
               Require_Kind (Item, Object_Value, "task");
               if Length (Doc, Item) /= 3 then
                  raise Improve.Data_Error with "audit task has unexpected fields";
               end if;
               Require_Member (Item, "id", String_Value);
               Require_Member (Item, "title", String_Value);
               Require_Member (Item, "contract_fingerprint", String_Value);
            end;
         end loop;
      end Validate_Tasks;

      procedure Validate_Publications is
         Items : constant Node := Member (Doc, Data, "publications");
      begin
         Require_Kind (Items, Array_Value, "publications");
         for Index in 1 .. Length (Doc, Items) loop
            declare
               Item : constant Node := Element (Doc, Items, Index);
            begin
               Require_Kind (Item, Object_Value, "publication");
               if Length (Doc, Item) /= 7 then
                  raise Improve.Data_Error with "audit publication has unexpected fields";
               end if;
               Require_Member (Item, "improve_task_id", String_Value);
               Require_Member (Item, "harness_task_id", String_Value);
               Require_Member (Item, "origin", String_Value);
               Require_Member (Item, "contract", String_Value);
               Require_Member (Item, "state", String_Value);
               Require_Member (Item, "core_state", String_Value);
               Require_Positive (Item, "plan_revision");
            end;
         end loop;
      end Validate_Publications;

      procedure Validate_Verifications is
         Items : constant Node := Member (Doc, Data, "verifications");
      begin
         Require_Kind (Items, Array_Value, "verifications");
         for Index in 1 .. Length (Doc, Items) loop
            declare
               Item : constant Node := Element (Doc, Items, Index);
            begin
               Require_Kind (Item, Object_Value, "verification");
               if Length (Doc, Item) /= 8 then
                  raise Improve.Data_Error with "audit verification has unexpected fields";
               end if;
               Require_Member (Item, "scope", String_Value);
               Require_Member (Item, "task_id", String_Value);
               Require_Positive (Item, "plan_revision");
               Require_Member (Item, "contract_fingerprint", String_Value);
               Require_Positive (Item, "assessment_id");
               Require_Member (Item, "outcome", String_Value);
               Require_Member (Item, "comparable", Boolean_Value);
               Require_Member (Item, "explanation", String_Value);
            end;
         end loop;
      end Validate_Verifications;

      Optional_Count : constant Natural :=
        (if Has_Member (Doc, Data, "next_cursor") then 1 else 0)
        + (if Has_Member (Doc, Data, "public_key") then 1 else 0)
        + (if Has_Member (Doc, Data, "signature") then 1 else 0);
   begin
      if Length (Doc, Data) /= 21 + Optional_Count then
         raise Improve.Data_Error with "audit data has missing or unexpected fields";
      end if;
      Require_Member (Data, "plan_id", String_Value);
      Require_Positive (Data, "revision");
      Require_Member (Data, "fingerprint", String_Value);
      Require_Member (Data, "approved", Boolean_Value);
      Require_Positive (Data, "project_id");
      Require_Member (Data, "project", String_Value);
      Require_Member (Data, "database_id", String_Value);
      Require_Positive (Data, "baseline_run");
      Require_Member (Data, "source_id", String_Value);
      Require_Member (Data, "policy_id", String_Value);
      Require_Member (Data, "toolchain_id", String_Value);
      Require_Member (Data, "evidence_id", String_Value);
      Require_Member (Data, "planner_id", String_Value);
      Require_Member (Data, "agent_provider", String_Value);
      Require_Optional_SHA256 (Data, "agent_model_sha256");
      Require_String_Array (Data, "finding_keys");
      Validate_Tasks;
      Validate_Publications;
      Validate_Verifications;
      Require_Member (Data, "canonical_payload", String_Value);
      Require_Member (Data, "bundle_digest", String_Value);
      if Has_Member (Doc, Data, "next_cursor") then
         Require_Member (Data, "next_cursor", String_Value);
      end if;
      if Has_Member (Doc, Data, "public_key") then
         Require_Member (Data, "public_key", String_Value);
      end if;
      if Has_Member (Doc, Data, "signature") then
         Require_Member (Data, "signature", String_Value);
      end if;
   end Validate_Audit_Contract;

   function Verify
     (Text               : String;
      Trusted_Public_Key : String := "") return Verification_Mode is
      Doc   : Document;
      Error : Jsonlib.Errors.Error_Info;
      Trusted : constant Ada.Streams.Stream_Element_Array :=
        (if Trusted_Public_Key = "" then [1 .. 0 => 0]
         else Decode (Trusted_Public_Key, 32, "trusted public key"));
   begin
      Jsonlib.Parsers.Parse
        (Text, Doc, Error,
         (Max_Depth => 64, Max_Length => Maximum_Artifact_Bytes,
          Duplicates => Jsonlib.Parsers.Refuse_Duplicates));
      if Error.Code /= Jsonlib.Errors.No_Error or else Kind (Doc, Root (Doc)) /= Object_Value then
         raise Improve.Data_Error with "audit document is not valid JSON";
      end if;
      declare
         Version : constant Node := Member (Doc, Root (Doc), "schema_version");
         Command : constant Node := Member (Doc, Root (Doc), "command");
         Data    : constant Node := Member (Doc, Root (Doc), "data");
         Payload : constant Node := (if Is_Present (Data) then Member (Doc, Data, "canonical_payload") else No_Node);
         Hash    : constant Node := (if Is_Present (Data) then Member (Doc, Data, "bundle_digest") else No_Node);
      begin
         if Length (Doc, Root (Doc)) /= 3 or else
           not Is_Present (Version) or else Kind (Doc, Version) /= Integer_Value or else
           As_Integer (Doc, Version) /= Long_Long_Integer (JSON_Format_Version) or else
           not Is_Present (Command) or else Kind (Doc, Command) /= String_Value or else
           As_String (Doc, Command) /= "audit" or else not Is_Present (Data) or else
           Kind (Doc, Data) /= Object_Value
         then
            raise Improve.Data_Error with "audit document has an invalid envelope";
         elsif not Is_Present (Payload) or else not Is_Present (Hash) or else
           Kind (Doc, Payload) /= String_Value or else Kind (Doc, Hash) /= String_Value
         then
            raise Improve.Data_Error with "audit document has no canonical payload and bundle digest";
         end if;
         Validate_Audit_Contract (Doc, Data);
         if Digest (As_String (Doc, Payload)) /= As_String (Doc, Hash) then
            raise Improve.Data_Error with "audit bundle digest mismatch";
         end if;
         declare
            Evidence_Doc : Document;
            Evidence     : constant Node := Copy (Evidence_Doc, Doc, Data);
            Removed      : Boolean;
         begin
            Removed := Remove_Member (Evidence_Doc, Evidence, "canonical_payload");
            Removed := Remove_Member (Evidence_Doc, Evidence, "bundle_digest") and then Removed;
            if Has_Member (Evidence_Doc, Evidence, "public_key") then
               Removed := Remove_Member (Evidence_Doc, Evidence, "public_key") and then Removed;
            end if;
            if Has_Member (Evidence_Doc, Evidence, "signature") then
               Removed := Remove_Member (Evidence_Doc, Evidence, "signature") and then Removed;
            end if;
            if not Removed or else Canonical_Data (Evidence_Doc, Evidence) /= As_String (Doc, Payload) then
               raise Improve.Data_Error with "audit canonical payload does not match exported evidence";
            end if;
         end;
         if Has_Member (Doc, Data, "signature") or else Has_Member (Doc, Data, "public_key") then
            if not Has_Member (Doc, Data, "signature") or else not Has_Member (Doc, Data, "public_key") then
               raise Improve.Data_Error with "audit signature and public key must appear together";
            elsif Trusted_Public_Key = "" then
               raise Improve.Argument_Error with
                 "signed audit verification requires a trusted public key";
            end if;
            declare
               use type CryptoLib.Errors.Status;
               Public_Node : constant Node := Member (Doc, Data, "public_key");
               Signature_Node : constant Node := Member (Doc, Data, "signature");
            begin
               if Kind (Doc, Public_Node) /= String_Value or else Kind (Doc, Signature_Node) /= String_Value then
                  raise Improve.Data_Error with "audit public key and signature must be hexadecimal strings";
               end if;
               declare
                  Pub : Ada.Streams.Stream_Element_Array (1 .. 32);
                  Sig : Ada.Streams.Stream_Element_Array (1 .. 64);
               begin
                  begin
                     Pub := Decode (As_String (Doc, Public_Node), 32, "audit public key");
                     Sig := Decode (As_String (Doc, Signature_Node), 64, "audit signature");
                  exception
                     when Improve.Argument_Error =>
                        raise Improve.Data_Error with "audit public key or signature is malformed";
                  end;
                  if Pub /= Trusted then
                     raise Improve.Data_Error with "audit public key does not match the trusted key";
                  elsif CryptoLib.Ed25519.Verify
                    (Trusted, Sig, Message (As_String (Doc, Hash))) /= CryptoLib.Errors.Ok
                  then
                     raise Improve.Data_Error with "audit Ed25519 signature mismatch";
                  end if;
               end;
            end;
            return Trusted_Signature;
         elsif Trusted_Public_Key /= "" then
            raise Improve.Data_Error with "trusted public key was supplied for an unsigned audit document";
         end if;
         return Digest_Only;
      end;
   end Verify;
end Improve.Audit_Artifacts;
