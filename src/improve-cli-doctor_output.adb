with Interfaces;

separate (Improve.CLI)
function Doctor_Output
  (Item     : Invocation;
   Settings : Improve.Config.Settings;
   Provider : access Improve.Refinement.Adapter'Class;
   Negative : out Boolean) return String is
   use type Interfaces.Unsigned_64;
   Report : Improve.Results.Diagnostic_Report :=
     Improve.Operations.Diagnostics.Run
       (Quality_Path (Item, Settings), State_Path (Item), To_String (Item.Project), Settings,
        Item.Release_Check,
        Improve.Operations.Storage_Limits (Settings));
   function Render return String is (Improve.Presentation.Diagnostics (Report));
   procedure Add
     (Name   : String;
      Status : Improve.Results.Diagnostic_Status;
      Detail : String) is
   begin
      Report.Checks.Append
        (Improve.Results.Diagnostic_Check'
           (Name   => To_Unbounded_String (Name),
            Status => Status,
            Detail => To_Unbounded_String (Detail)));
      if Status = Improve.Results.Diagnostic_Fail then Report.Healthy := False; end if;
   end Add;
begin
   if Settings.Agent_Enabled then
      if Provider = null then
         Add ("agent-runtime", Improve.Results.Diagnostic_Fail, "optional model runtime is unavailable");
      else
         declare
            Identity : constant Improve.Refinement.Adapter_Provenance :=
              Improve.Refinement.Provenance (Provider.all);
            Digest   : constant String := To_String (Identity.Model_SHA256);
            Expected : constant String := To_String (Settings.Agent_Model_SHA256);
            function Count (Value : Interfaces.Unsigned_64) return String is
              (Ada.Strings.Fixed.Trim (Interfaces.Unsigned_64'Image (Value), Ada.Strings.Both));
         begin
            if Digest'Length /= 64 or else Digest = [1 .. 64 => '0'] or else
              (for some C of Digest => C not in '0' .. '9' | 'a' .. 'f')
            then
               Add
                 ("agent-runtime", Improve.Results.Diagnostic_Fail,
                  "GGUF loading or response-schema preparation failed");
            else
               Add
                 ("agent-runtime", Improve.Results.Diagnostic_Pass,
                  "GGUF and response schema opened through " & To_String (Identity.Provider_Id));
               Add
                 ("agent-model-digest", Improve.Results.Diagnostic_Pass,
                  "opened model SHA-256 " & Digest);
               Add
                 ("agent-model-path",
                  (if Length (Identity.Canonical_Path) = 0 then Improve.Results.Diagnostic_Warning
                   else Improve.Results.Diagnostic_Pass),
                  (if Length (Identity.Canonical_Path) = 0 then "canonical model path is unavailable"
                   else To_String (Identity.Canonical_Path)));
               Add
                 ("agent-model-architecture",
                  (if Length (Identity.Architecture) = 0 then Improve.Results.Diagnostic_Warning
                   else Improve.Results.Diagnostic_Pass),
                  (if Length (Identity.Architecture) = 0 then "model architecture is unavailable"
                   else To_String (Identity.Architecture) &
                     (if Length (Identity.Model_Name) = 0 then ""
                      else " (" & To_String (Identity.Model_Name) & ")")));
               Add
                 ("agent-model-size",
                  (if Identity.Model_Bytes = 0 or else Identity.Model_Parts = 0
                   then Improve.Results.Diagnostic_Warning else Improve.Results.Diagnostic_Pass),
                  (if Identity.Model_Bytes = 0 or else Identity.Model_Parts = 0
                   then "model size or file count is unavailable"
                   else Count (Identity.Model_Bytes) & " bytes across " & Number (Identity.Model_Parts) &
                     (if Identity.Model_Parts = 1 then " file" else " files")));
               Add
                 ("agent-model-pin",
                  (if Expected /= "" and then Digest /= Expected then Improve.Results.Diagnostic_Fail
                   elsif Expected = "" then Improve.Results.Diagnostic_Warning
                   else Improve.Results.Diagnostic_Pass),
                  (if Expected /= "" and then Digest /= Expected
                   then "opened model digest does not match pin"
                   elsif Expected = "" then "model digest is not pinned"
                   else "opened model digest matches pin"));
            end if;
         end;
      end if;
   end if;
   Negative := not Report.Healthy;
   if Item.Format = JSON_Format then return Improve.JSON.Diagnostics (Report); end if;
   return Render_Terminal (Item, Render'Access);
end Doctor_Output;
