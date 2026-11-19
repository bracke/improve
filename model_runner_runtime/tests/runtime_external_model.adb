with Ada.Containers;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Hostkit.Fs;
with Improve.CLI;
with Improve.Model;
with Improve.Refinement.Model_Adapter;
with Improve.Refinement.Model_Runner_Client;
with Improve.Refinement.Model_Runner_Runtime;
with Improve.State;
with Improve.Storage;
with Model_Runner.Errors;
with Model_Runner.Inference;
with Project_Tools.Files;
with Runtime_Test_Fixtures;

--  Optional compatibility smoke check for a caller-supplied production GGUF.
procedure Runtime_External_Model is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Real_Time.Time;
   use type Improve.Refinement.Response_Status;
   use type Interfaces.Unsigned_64;

   Variable : constant String := "IMPROVE_TEST_MODEL";

   procedure Require_Budget (Name : String; Actual : Duration) is
   begin
      Ada.Text_IO.Put_Line
        ("metric." & Name & "=" &
         Ada.Strings.Fixed.Trim (Duration'Image (Actual), Ada.Strings.Both));
      if Ada.Environment_Variables.Exists ("IMPROVE_TEST_MAX_" & Name) and then
        Actual > Duration'Value (Ada.Environment_Variables.Value ("IMPROVE_TEST_MAX_" & Name))
      then
         raise Program_Error with Name & " exceeded its configured performance budget";
      end if;
   exception
      when Constraint_Error =>
         raise Program_Error with "IMPROVE_TEST_MAX_" & Name & " is not a valid duration";
   end Require_Budget;
begin
   if not Ada.Environment_Variables.Exists (Variable) then
      return;
   end if;

   declare
      Path : constant String := Ada.Environment_Variables.Value (Variable);
      Name : constant String :=
        (if Ada.Environment_Variables.Exists ("IMPROVE_TEST_MODEL_NAME")
         then Ada.Environment_Variables.Value ("IMPROVE_TEST_MODEL_NAME")
         else "external-compatibility-model");
      Expected : constant String :=
        (if Ada.Environment_Variables.Exists ("IMPROVE_TEST_MODEL_SHA256")
         then Ada.Environment_Variables.Value ("IMPROVE_TEST_MODEL_SHA256")
         else "");
      Runtime : aliased Improve.Refinement.Model_Runner_Runtime.Runtime;
      Status  : Model_Runner.Errors.Error_Info;
      Started : Ada.Real_Time.Time;
   begin
      if Expected'Length /= 64 or else
        (for some C of Expected => C not in '0' .. '9' | 'a' .. 'f')
      then
         raise Program_Error with
           "IMPROVE_TEST_MODEL_SHA256 must pin the production GGUF with a lower-case SHA-256";
      end if;
      Started := Ada.Real_Time.Clock;
      Improve.Refinement.Model_Runner_Runtime.Open (Runtime, Name, Path, Status => Status);
      Require_Budget ("OPEN_SECONDS", Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started));
      if Model_Runner.Errors.Is_Error (Status) then
         raise Program_Error with
           "external GGUF did not open: " & Model_Runner.Errors.Diagnostic_Code (Status.Code);
      end if;
      declare
         Identity : constant Model_Runner.Inference.Model_Provenance :=
           Improve.Refinement.Model_Runner_Runtime.Provenance (Runtime);
         Digest : constant String :=
           Improve.Refinement.Model_Runner_Runtime.Model_SHA256 (Runtime);
      begin
         if not Improve.Refinement.Model_Runner_Runtime.Is_Open (Runtime)
           or else Length (Identity.Architecture) = 0
           or else Identity.Bytes = 0
           or else Identity.Parts = 0
           or else Digest = [1 .. 64 => '0']
         then
            raise Program_Error with "external GGUF lacks usable runtime provenance";
         elsif Expected /= "" and then Digest /= Expected then
            raise Program_Error with "external GGUF digest does not match IMPROVE_TEST_MODEL_SHA256";
         end if;
         Ada.Text_IO.Put_Line ("metric.MODEL_SHA256=" & Digest);
         Ada.Text_IO.Put_Line ("metric.MODEL_ARCHITECTURE=" & To_String (Identity.Architecture));
         Ada.Text_IO.Put_Line
           ("metric.MODEL_BYTES=" &
            Ada.Strings.Fixed.Trim (Interfaces.Unsigned_64'Image (Identity.Bytes), Ada.Strings.Both));
      end;
      declare
         Context : constant Improve.Refinement.Planning_Context :=
           (Project_Id      => 1,
            Project_Name    => To_Unbounded_String ("production-model-ci"),
            Project_Root    => To_Unbounded_String ("."),
            Assessment_Run  => 1,
            Policy          => To_Unbounded_String ("compatibility"),
            Toolchain       => To_Unbounded_String ("gnat-15"),
            Required_Schema => To_Unbounded_String (Improve.Refinement.Response_Schema),
            Byte_Count      => 0,
            Maximum_Response_Bytes => 4_096,
            others          => <>);
         Response : Improve.Refinement.Agent_Response;
      begin
         Started := Ada.Real_Time.Clock;
         Improve.Refinement.Model_Runner_Runtime.Infer
           (Runtime, Name, Context, Improve.Refinement.Response_Schema,
            Timeout_Seconds => 180, Maximum_Response_Bytes => 4_096, Response => Response);
         Require_Budget
           ("INFER_SECONDS", Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started));
         if Response.Status /= Improve.Refinement.Proposal_Ready then
            raise Program_Error with
              "production GGUF constrained completion failed: " & To_String (Response.Diagnostic);
         end if;
      end;

      declare
         Root        : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-production-model");
         Database    : constant String := Root & "/quality.db";
         State_Path  : constant String := Root & "/state.db";
         Wrong_State : constant String := Root & "/wrong-state.db";
         Target      : constant String := Root & "/project";
         Project     : Positive;

         function Arguments (State, Digest : String) return Improve.CLI.String_Vectors.Vector is
            Result : Improve.CLI.String_Vectors.Vector;
         begin
            Result.Append ("plan");
            Result.Append ("--database");
            Result.Append (Database);
            Result.Append ("--state");
            Result.Append (State);
            Result.Append ("--project");
            Result.Append (Ada.Strings.Fixed.Trim (Positive'Image (Project), Ada.Strings.Both));
            Result.Append ("--agent-model");
            Result.Append (Name);
            Result.Append ("--agent-model-path");
            Result.Append (Path);
            Result.Append ("--agent-model-sha256");
            Result.Append (Digest);
            Result.Append ("--progress");
            Result.Append ("never");
            Result.Append ("--format");
            Result.Append ("json");
            return Result;
         end Arguments;
      begin
         Runtime_Test_Fixtures.Build_Quality_Fixture (Database, Target, Project);
         declare
            Client : aliased Improve.Refinement.Model_Runner_Client.Client :=
              Improve.Refinement.Model_Runner_Client.Create (Runtime'Access, Name);
            Provider : aliased Improve.Refinement.Model_Adapter.Provider (Client'Access);
            Wrong : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Arguments (Wrong_State, [1 .. 64 => '0']), Provider'Access);
            Result : Improve.CLI.Outcome;
         begin
            if Wrong.Exit_Code /= Improve.CLI.Unavailable_Exit or else Ada.Directories.Exists (Wrong_State) then
               raise Program_Error with "CLI accepted a wrong production-model digest or persisted its plan";
            end if;
            Started := Ada.Real_Time.Clock;
            Result := Improve.CLI.Execute (Arguments (State_Path, Expected), Provider'Access);
            Require_Budget
              ("CLI_SECONDS", Ada.Real_Time.To_Duration (Ada.Real_Time.Clock - Started));
            if Result.Exit_Code /= 0 then
               raise Program_Error with "production-model CLI plan failed: " & To_String (Result.Errors);
            end if;
         end;
         declare
            Store : Improve.Storage.Store;
         begin
            Improve.Storage.Open (Store, State_Path, Writable => False);
            declare
               Values : constant Improve.State.Summary_Vectors.Vector := Improve.Storage.List_All (Store);
            begin
               if Values.Length /= 1 then
                  raise Program_Error with "production-model CLI did not persist exactly one plan";
               end if;
               declare
                  Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Storage.Load (Store, To_String (Values.First_Element.Plan_Id));
               begin
                  if To_String (Plan.Agent_Model_SHA256) /= Expected or else
                    Length (Plan.Agent_Provider_Id) = 0 or else
                    Ada.Strings.Fixed.Index (To_String (Plan.Planner_Id), Expected) = 0
                  then
                     raise Program_Error with "persisted CLI plan lost production-model provenance";
                  end if;
               end;
            end;
            Improve.Storage.Close (Store);
         exception
            when others =>
               Improve.Storage.Close (Store);
               raise;
         end;
         Project_Tools.Files.Delete_Tree (Root);
      exception
         when others =>
            if Ada.Directories.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
            raise;
      end;
      Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
   exception
      when others =>
         Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
         raise;
   end;
end Runtime_External_Model;
