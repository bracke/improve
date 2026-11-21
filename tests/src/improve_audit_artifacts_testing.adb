with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with Improve;
with Improve.Audit_Artifacts;
with Improve.CLI;
with Improve.CLI.Testing;
with Improve.JSON;
with Improve.Model;
with Improve.Operations.Audit;
with Improve.Results;
with Improve.Storage;
with Improve_Test_Support;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Improve_Audit_Artifacts_Testing is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.Audit_Artifacts.Verification_Mode;

   procedure Check is
      Seed      : constant String := [1 .. 64 => '0'];
      Canonical : constant String := "{""approved"":false}";
      Digest    : constant String := Improve.Stable_Digest (Canonical);
      Public_Key, Signature : Unbounded_String;
      Rejected : Boolean := False;
      Plan : constant Improve.Model.Plan_Revision :=
        (Project  => (Id => 1, others => <>),
         Baseline => (Project_Id => 1, Run_Id => 1, others => <>),
         others   => <>);
      Bundle : constant Improve.Results.Audit_Bundle :=
        (Plan => Plan, Approved => False,
         History => (Selected_Revision => 1, Publications => <>, Verifications => <>));

      procedure Expect_Rejected
        (Text, Context : String;
         Trusted_Key   : String := "") is
         Was_Rejected : Boolean := False;
      begin
         begin
            declare
               Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
                 Improve.Audit_Artifacts.Verify (Text, Trusted_Key);
               pragma Unreferenced (Mode);
            begin
               null;
            end;
         exception
            when Improve.Data_Error | Improve.Argument_Error => Was_Rejected := True;
         end;
         Assert (Was_Rejected, Context & " audit artifact was accepted");
      end Expect_Rejected;
   begin
      Improve.Audit_Artifacts.Sign (Digest, Seed, Public_Key, Signature);
      declare
         Unsigned : constant String := Improve.JSON.Audit (Bundle);
         Text     : constant String := Improve.JSON.Audit (Bundle, Signing_Seed => Seed);
         Model_Digest_Field : constant String := """agent_model_sha256"":""""";
         Model_Digest_Position : constant Natural :=
           Ada.Strings.Fixed.Index (Unsigned, Model_Digest_Field);
      begin
         Assert (Model_Digest_Position > 0, "audit omitted agent model digest field");
         declare
            Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
              Improve.Audit_Artifacts.Verify (Unsigned);
         begin
            Assert (Mode = Improve.Audit_Artifacts.Digest_Only, "unsigned artifact did not verify");
         end;
         declare
            Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
              Improve.Audit_Artifacts.Verify (Text, To_String (Public_Key));
         begin
            Assert
              (Mode = Improve.Audit_Artifacts.Trusted_Signature,
               "signed artifact did not report trusted verification");
         end;
         Expect_Rejected
           (Unsigned (Unsigned'First .. Model_Digest_Position + Model_Digest_Field'Length - 2) &
            "x" & Unsigned (Model_Digest_Position + Model_Digest_Field'Length - 1 .. Unsigned'Last),
            "invalid agent model digest");
         Expect_Rejected (Text, "signed without trust anchor");
         declare
            Wrong_Public_Key, Wrong_Signature : Unbounded_String;
         begin
            Improve.Audit_Artifacts.Sign
              (Digest, '1' & [2 .. 64 => '0'], Wrong_Public_Key, Wrong_Signature);
            Expect_Rejected (Text, "signed with wrong trust anchor", To_String (Wrong_Public_Key));
         end;
         Expect_Rejected
           (Text (Text'First .. Text'Last - 4) &
            (if Text (Text'Last - 3) = '0' then "1" else "0") & Text (Text'Last - 2 .. Text'Last),
            "altered signed", To_String (Public_Key));
      end;
      declare
         Prefix : constant String :=
           "{""schema_version"":2,""command"":""audit"",""data"":{""approved"":false," &
           """canonical_payload"":""" & Jsonlib.Serializers.Escape (Canonical) &
           """,""bundle_digest"":""";
         Unsigned : constant String := Prefix & Digest & """}}";
      begin
         Expect_Rejected (Unsigned, "schema-incomplete");
         Expect_Rejected
           (Unsigned (Unsigned'First .. Unsigned'Last - 1) & ",""untrusted"":true}",
            "extended envelope");
         Expect_Rejected ("{", "invalid JSON");
         Expect_Rejected
           ("{""schema_version"":1,""command"":""audit"",""data"":{}}", "invalid envelope");
         Expect_Rejected
           ("{""schema_version"":2,""command"":""audit"",""data"":{""approved"":false}}",
            "missing integrity fields");
         Expect_Rejected (Prefix & "bad""}}", "mismatched digest");
         Expect_Rejected
           ("{""schema_version"":2,""command"":""audit"",""data"":{""approved"":true," &
            """canonical_payload"":""{""approved"":false}"",""bundle_digest"":""" & Digest & """}}",
            "mismatched canonical evidence");
         Expect_Rejected (Prefix & Digest & """,""signature"":""00""}}", "unpaired signature");
         Expect_Rejected
           (Prefix & Digest & """,""public_key"":""00"",""signature"":""00""}}",
            "malformed signature");
      end;
      begin
         Improve.Audit_Artifacts.Sign (Digest, [1 .. 63 => '0'], Public_Key, Signature);
      exception
         when Improve.Argument_Error => Rejected := True;
      end;
      Assert (Rejected, "short audit signing seed was accepted");
      Rejected := False;
      begin
         Improve.Audit_Artifacts.Sign (Digest, [1 .. 64 => 'g'], Public_Key, Signature);
      exception
         when Improve.Argument_Error => Rejected := True;
      end;
      Assert (Rejected, "non-hexadecimal audit signing seed was accepted");
      Improve.Audit_Artifacts.Sign (Digest, 'A' & [2 .. 64 => '0'], Public_Key, Signature);
   end Check;

   procedure Check_CLI is
      use Improve_Test_Support;

      Data       : constant Fixture := Build_Fixture ("audit_bundle");
      Seed       : constant String := [1 .. 64 => '0'];
      Draft      : Improve.Model.Plan_Revision := Draft_For (Data);
      Store      : Improve.Storage.Store;
      State_Path : constant String := To_String (Data.Directory) & "/improve.db";
   begin
      Improve.Storage.Open (Store, State_Path, Writable => True);
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Draft);
      begin
         Draft := Saved.Plan;
      end;
      Improve.Storage.Approve (Store, To_String (Draft.Plan_Id), Draft.Revision);
      Improve.Storage.Close (Store);
      declare
         Bundle : constant Improve.Results.Audit_Bundle :=
           Improve.Operations.Audit.Run (State_Path, To_String (Draft.Plan_Id));
         Audit_Text  : constant String := Improve.JSON.Audit (Bundle);
         Signed_Text : constant String := Improve.JSON.Audit (Bundle, Signing_Seed => Seed);
         Audit_Path  : constant String := To_String (Data.Directory) & "/audit.json";
         Signed_Path : constant String := To_String (Data.Directory) & "/signed-audit.json";
         Public_Path : constant String := To_String (Data.Directory) & "/audit.pub";
         Large_Path  : constant String := To_String (Data.Directory) & "/large-audit.json";
         Empty_Path  : constant String := To_String (Data.Directory) & "/empty-audit.json";
         Mutable_Path : constant String := To_String (Data.Directory) & "/mutable-audit.json";
         Missing     : constant String := To_String (Data.Directory) & "/missing.json";
         Missing_Key : constant String := To_String (Data.Directory) & "/missing.key";
         Public_Key, Signature : Unbounded_String;
      begin
         Assert
           (Bundle.Approved and then Bundle.Plan.Fingerprint = Draft.Fingerprint and then
            Ada.Strings.Fixed.Index (Audit_Text, """command"":""audit""") > 0,
            "read-only audit bundle omitted exact plan approval or provenance");
         declare
            Oversized : Improve.Results.Audit_Bundle := Bundle;
            Chunk     : constant String := [1 .. 4_096 => ASCII.NUL];
            Title     : Unbounded_String;
            Target    : constant Natural :=
              Improve.Audit_Artifacts.Maximum_Artifact_Bytes / 13 + 1_024;
            Rejected  : Boolean := False;
         begin
            while Length (Title) + Chunk'Length <= Target loop
               Append (Title, Chunk);
            end loop;
            Append (Title, Chunk (Chunk'First .. Target - Length (Title)));
            Oversized.Plan.Tasks (Oversized.Plan.Tasks.First_Index).Title := Title;
            begin
               declare
                  Text : constant String := Improve.JSON.Audit (Oversized);
                  pragma Unreferenced (Text);
               begin
                  null;
               end;
            exception
               when Improve.Data_Error => Rejected := True;
            end;
            Assert (Rejected, "audit export exceeded the verifier's shared size contract");
         end;
         Project_Tools.Files.Write_Text_File (Audit_Path, Audit_Text);
         Project_Tools.Files.Write_Text_File (Signed_Path, Signed_Text);
         declare
            Large_Bundle : Improve.Results.Audit_Bundle := Bundle;
         begin
            Large_Bundle.Plan.Tasks (Large_Bundle.Plan.Tasks.First_Index).Title :=
              To_Unbounded_String ([1 .. 70_000 => 'x']);
            Project_Tools.Files.Write_Text_File (Large_Path, Improve.JSON.Audit (Large_Bundle));
         end;
         Improve.Audit_Artifacts.Sign ("public-key-derivation", Seed, Public_Key, Signature);
         Project_Tools.Files.Write_Text_File (Public_Path, To_String (Public_Key) & ASCII.LF);
         declare
            File : Ada.Streams.Stream_IO.File_Type;
         begin
            Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Empty_Path);
            Ada.Streams.Stream_IO.Close (File);
         end;
         Project_Tools.Files.Write_Text_File (Mutable_Path, "same-size-a");
         Assert
           (Improve.CLI.Testing.Rejects_Between_Pass_Change
              (Mutable_Path, "same-size-b", Improve.Audit_Artifacts.Maximum_Artifact_Bytes),
            "bounded input reader accepted a same-size mutation between passes");
         declare
            Verified : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Audit_Path));
            Verified_JSON : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Audit_Path & "|--format|json"));
            Large_Verified : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Large_Path));
            Signed_Without_Trust : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Signed_Path));
            Signed_Verified : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute
                (Args ("audit|verify|" & Signed_Path & "|--verification-key|" & Public_Path));
            Empty : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Empty_Path));
            Directory_Input : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & To_String (Data.Directory)));
            Unavailable : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Args ("audit|verify|" & Missing & "|--format|json"));
            Ignored_Key : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute
                (Args ("audit|" & To_String (Draft.Plan_Id) & "|--state|" & State_Path &
                   "|--signing-key|" & Missing_Key));
            Missing_Key_Result : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute
                (Args ("audit|" & To_String (Draft.Plan_Id) & "|--state|" & State_Path &
                   "|--format|json|--signing-key|" & Missing_Key));
            Missing_Verification_Key : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute
                (Args ("audit|verify|" & Signed_Path & "|--verification-key|" & Missing_Key));
         begin
            Assert
              (Verified.Exit_Code = 0 and then Verified_JSON.Exit_Code = 0 and then
               Large_Verified.Exit_Code = 0 and then
               Ada.Strings.Fixed.Index (To_String (Verified.Output), "digest is valid") > 0 and then
               Ada.Strings.Fixed.Index (To_String (Verified_JSON.Output), """kind"":""integrity""") > 0 and then
               Ada.Strings.Fixed.Index
                 (To_String (Verified_JSON.Output), """text"":""digest_valid_unsigned""") > 0,
               "unsigned audit verification output contract failed: " & To_String (Verified.Errors));
            Assert
              (Signed_Without_Trust.Exit_Code = Improve.CLI.Argument_Exit and then
               Signed_Verified.Exit_Code = 0 and then
               Ada.Strings.Fixed.Index (To_String (Signed_Verified.Output), "trusted public key") > 0,
               "signed audit trust-anchor contract failed: " & To_String (Signed_Verified.Errors));
            Assert
              (Empty.Exit_Code = Improve.CLI.Unavailable_Exit and then
               Directory_Input.Exit_Code = Improve.CLI.Unavailable_Exit and then
               Unavailable.Exit_Code = Improve.CLI.Unavailable_Exit and then
               Ada.Strings.Fixed.Index (To_String (Unavailable.Errors), "IMP-E-DEPENDENCY") > 0 and then
               Ignored_Key.Exit_Code = Improve.CLI.Argument_Exit and then
               Missing_Key_Result.Exit_Code = Improve.CLI.Unavailable_Exit and then
               Missing_Verification_Key.Exit_Code = Improve.CLI.Unavailable_Exit,
               "audit file-error contract failed");
         end;
      end;
      declare
         Common : constant String := "|--state|" & State_Path & "|--format|json";
         Audit  : constant Improve.CLI.Outcome :=
           Improve.CLI.Execute
             (Args ("audit|" & To_String (Draft.Plan_Id) & Common & "|--limit|1|--cursor|0"));
         Audit_Terminal : constant Improve.CLI.Outcome :=
           Improve.CLI.Execute (Args ("audit|" & To_String (Draft.Plan_Id) & "|--state|" & State_Path));
      begin
         Assert
           (Audit.Exit_Code = 0 and then Audit_Terminal.Exit_Code = 0,
            "paged or terminal audit export failed");
      end;
      Remove (Data);
   exception
      when others =>
         Improve.Storage.Close (Store);
         Remove (Data);
         raise;
   end Check_CLI;
end Improve_Audit_Artifacts_Testing;
