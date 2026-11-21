with Ada.Containers;
with Ada.Strings.Unbounded;
with Improve.Audit_Artifacts;
with Improve.CLI_Support;
with Improve.JSON;
with Improve.Operations.Audit;
with Improve.Presentation;
with Improve.Results;

package body Improve.CLI_Audit_Output is
   use Ada.Strings.Unbounded;
   use Improve.CLI;
   use Improve.CLI_Support;
   use Improve.Config;
   use type Ada.Containers.Count_Type;
   use type Improve.Audit_Artifacts.Verification_Mode;

   LF : constant Character := Character'Val (10);
   function Render
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return String is
   begin
      if Item.Has_Signing_Key and then Item.Format /= JSON_Format then
         raise Argument_Error with "--signing-key requires --format json";
      end if;
      if Item.Audit_Verify then
         declare
            Text : constant String :=
              Read_Bounded_File
                (To_String (Item.Target), "audit document", Improve.Audit_Artifacts.Maximum_Artifact_Bytes);
            Trusted_Key : constant String :=
              (if Item.Has_Verification_Key then
                 Read_Hex_Key (To_String (Item.Verification_Key), "audit verification key")
               else "");
         begin
            if Text = "" then
               raise Dependency_Error with "audit document is unavailable or empty";
            elsif Item.Has_Verification_Key and then Trusted_Key = "" then
               raise Dependency_Error with "audit verification key is unavailable or empty";
            end if;
            declare
               Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
                 Improve.Audit_Artifacts.Verify (Text, Trusted_Key);
               Detail : constant String :=
                 (case Mode is
                     when Improve.Audit_Artifacts.Digest_Only => "digest_valid_unsigned",
                     when Improve.Audit_Artifacts.Trusted_Signature => "trusted_signature_valid");
            begin
               return
                 (if Item.Format = JSON_Format then Improve.JSON.Text ("audit verify", "integrity", Detail)
                  elsif Mode = Improve.Audit_Artifacts.Digest_Only then
                    "Unsigned audit bundle digest is valid; authenticity was not verified." & LF
                  else "Audit bundle signature is valid for the trusted public key." & LF);
            end;
         end;
      end if;
      declare
         Limit : constant Positive :=
           (if Item.Has_Limit or else Item.Has_Cursor then Page_Limit (Item, Settings)
            else Settings.Maximum_Output_Items);
         Bundle : Improve.Results.Audit_Bundle :=
           Improve.Operations.Audit.Run
             (State_Path (Item), To_String (Item.Target), Item.Revision,
              Query_Maximum (Item, Settings, Settings.Maximum_History_Items),
              Improve.Operations.Storage_Limits (Settings));
         Next : Unbounded_String;
         function Render_Summary return String is
           (Improve.Presentation.Audit (Bundle) &
            (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
      begin
         if Item.Has_Limit or else Item.Has_Cursor then
            if Item.Cursor >= Natural (Bundle.History.Publications.Length) then
               Bundle.History.Publications.Clear;
            elsif Item.Cursor > 0 then
               Bundle.History.Publications.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
            end if;
            if Item.Cursor >= Natural (Bundle.History.Verifications.Length) then
               Bundle.History.Verifications.Clear;
            elsif Item.Cursor > 0 then
               Bundle.History.Verifications.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
            end if;
            if Natural (Bundle.History.Publications.Length) > Limit or else
              Natural (Bundle.History.Verifications.Length) > Limit
            then
               Next := To_Unbounded_String (Number (Item.Cursor + Limit));
            end if;
            if Natural (Bundle.History.Publications.Length) > Limit then
               Bundle.History.Publications.Delete_Last
                 (Bundle.History.Publications.Length - Ada.Containers.Count_Type (Limit));
            end if;
            if Natural (Bundle.History.Verifications.Length) > Limit then
               Bundle.History.Verifications.Delete_Last
                 (Bundle.History.Verifications.Length - Ada.Containers.Count_Type (Limit));
            end if;
         end if;
         if Item.Format = JSON_Format then
            declare
               Seed : constant String :=
                 (if Item.Has_Signing_Key then
                    Read_Hex_Key (To_String (Item.Signing_Key), "audit signing key") else "");
            begin
               if Item.Has_Signing_Key and then Seed = "" then
                  raise Dependency_Error with "audit signing key is unavailable or empty";
               end if;
               return Improve.JSON.Audit (Bundle, To_String (Next), Seed);
            end;
         end if;
         return Render_Terminal (Item, Render_Summary'Access);
      end;
   end Render;
end Improve.CLI_Audit_Output;
