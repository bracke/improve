with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with Improve.Audit_Artifacts;
with Improve.Harness_States;
with Improve.JSON;
with Improve.Presentation;
with Improve.State;
with Improve.Tasks;
with Improve_JSON_Schema_Testing;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Improve_JSON_Output_Testing is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;

   procedure Check_All (Plan : Improve.Model.Plan_Revision) is
      use type Jsonlib.Errors.Error_Code;
      Schema_Directory : constant String :=
        (if Project_Tools.Files.File_Exists ("schemas/improve-output-v2.schema.json")
         then "schemas" else "../schemas");
      Schema : constant String :=
        Project_Tools.Files.Read_Raw_File (Schema_Directory & "/improve-output-v2.schema.json");
      Documents : Improve.Model.UString_Vectors.Vector;
      Empty_Plans : Improve.State.Summary_Vectors.Vector;
      Empty_Tasks : Improve.Tasks.View_Vectors.Vector;
      Empty_Status : Improve.Tasks.Status_Vectors.Vector;
      Empty_Findings : Improve.Model.Finding_Vectors.Vector;
      History : Improve.State.Inspection_History :=
        (Selected_Revision => 1, Publications => <>, Verifications => <>);
      procedure Add (Text : String) is
      begin
         Documents.Append (To_Unbounded_String (Text));
      end Add;

      procedure Check_Audit_Contract_Parity (Text : String) is
         Schema_Doc : Jsonlib.Documents.Document;
         Error      : Jsonlib.Errors.Error_Info;
      begin
         Jsonlib.Parsers.Parse (Schema, Schema_Doc, Error);
         Assert (Error.Code = Jsonlib.Errors.No_Error, "audit parity schema could not be parsed");
         declare
            Definitions : constant Jsonlib.Documents.Node := Schema_Doc.Member (Schema_Doc.Root, "$defs");
            Audit_Rule  : constant Jsonlib.Documents.Node := Schema_Doc.Member (Definitions, "audit");
            Required    : constant Jsonlib.Documents.Node := Schema_Doc.Member (Audit_Rule, "required");
         begin
            for Index in 1 .. Schema_Doc.Length (Required) loop
               declare
                  Name        : constant String := Schema_Doc.As_String (Schema_Doc.Element (Required, Index));
                  Instance    : Jsonlib.Documents.Document;
                  Parse_Error : Jsonlib.Errors.Error_Info;
                  Rejected    : Boolean := False;
               begin
                  Jsonlib.Parsers.Parse (Text, Instance, Parse_Error);
                  Assert (Parse_Error.Code = Jsonlib.Errors.No_Error, "audit parity fixture could not be parsed");
                  declare
                     Data    : constant Jsonlib.Documents.Node := Instance.Member (Instance.Root, "data");
                     Removed : constant Boolean := Instance.Remove_Member (Data, Name);
                     Mutated : constant String := Jsonlib.Serializers.To_String (Instance);
                     Problem : constant String :=
                       Improve_JSON_Schema_Testing.Validate
                         (Schema_Directory, "improve-output-v2.schema.json", Mutated);
                  begin
                     Assert (Removed and then Problem /= "", "schema accepted audit without required field " & Name);
                     begin
                        declare
                           Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
                             Improve.Audit_Artifacts.Verify (Mutated);
                           pragma Unreferenced (Mode);
                        begin
                           null;
                        end;
                     exception
                        when Improve.Data_Error | Improve.Argument_Error => Rejected := True;
                     end;
                     Assert (Rejected, "verifier accepted audit without required field " & Name);
                  end;
               end;
            end loop;
         end;
         declare
            Instance    : Jsonlib.Documents.Document;
            Parse_Error : Jsonlib.Errors.Error_Info;
            Rejected    : Boolean := False;
         begin
            Jsonlib.Parsers.Parse (Text, Instance, Parse_Error);
            Assert (Parse_Error.Code = Jsonlib.Errors.No_Error, "audit extension fixture could not be parsed");
            declare
               Data : constant Jsonlib.Documents.Node := Instance.Member (Instance.Root, "data");
            begin
               Instance.Insert (Data, "unexpected", Instance.New_Boolean (True));
            end;
            declare
               Mutated : constant String := Jsonlib.Serializers.To_String (Instance);
               Problem : constant String :=
                 Improve_JSON_Schema_Testing.Validate
                   (Schema_Directory, "improve-output-v2.schema.json", Mutated);
            begin
               Assert (Problem /= "", "schema accepted an unexpected audit field");
               begin
                  declare
                     Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
                       Improve.Audit_Artifacts.Verify (Mutated);
                     pragma Unreferenced (Mode);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error | Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "verifier accepted an unexpected audit field");
            end;
         end;
      end Check_Audit_Contract_Parity;
   begin
      Assert
        (Ada.Strings.Fixed.Index (Schema, """command"": { ""const"": ""audit""") > 0 and then
         Ada.Strings.Fixed.Index (Schema, """command"": { ""const"": ""error""") > 0 and then
         Ada.Strings.Fixed.Index (Schema, """additionalProperties"": false") > 0,
         "command-specific JSON schema branches are incomplete");
      Assert
        (Ada.Strings.Fixed.Index (Improve.Presentation.Plan_Graph (Plan), "digraph improve_plan") = 1,
         "DOT graph rendering failed");
      declare
         Task_Id  : constant Unbounded_String := Plan.Tasks.First_Element.Id;
         Contract : constant String := Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Task_Id);
      begin
         History.Selected_Revision := Plan.Revision;
         History.Publications.Append
           (Improve.State.Publication_Record'
              (Improve_Task_Id => Task_Id,
               Harness_Task_Id => To_Unbounded_String ("TASK-AUDIT-001"),
               Origin          => To_Unbounded_String ("improve:audit-fixture"),
               Contract        => To_Unbounded_String (Contract),
               State           => To_Unbounded_String ("candidate"),
               Core_State      => Improve.Harness_States.Parse_Core ("candidate"),
               Plan_Revision   => Plan.Revision));
         History.Verifications.Append
           (Improve.State.Verification_Record'
              (Scope                => Improve.Model.Task_Evaluation,
               Task_Id              => Task_Id,
               Plan_Revision        => Plan.Revision,
               Contract_Fingerprint => To_Unbounded_String (Contract),
               Assessment_Id        => 1,
               Outcome              => Improve.Model.Verified,
               Comparable           => True,
               Explanation          => To_Unbounded_String ("audit contract parity fixture")));
      end;
      Add (Improve.JSON.Text ("config", "text", "value"));
      Add (Improve.JSON.Projects ((others => <>)));
      Add
        (Improve.JSON.Findings
           ((Project_Id => 1, Project => Null_Unbounded_String, Run_Id => 1,
             Assessment_Id | Snapshot_Id => Null_Unbounded_String, Values => Empty_Findings)));
      Add (Improve.JSON.Plan (Plan, False));
      Add (Improve.JSON.Plan_Graph (Plan));
      Add (Improve.JSON.Plans (Empty_Plans));
      Add (Improve.JSON.Plan_Approval (Plan));
      Add (Improve.JSON.Plan_Comparison ((others => <>), False));
      Add (Improve.JSON.Diagnostics ((others => <>)));
      Add (Improve.JSON.Audit ((Plan => Plan, Approved => False, History => History)));
      Add (Improve.JSON.Audit ((Plan => Plan, Approved => False, History => History), Next_Cursor => "2"));
      Add
        (Improve.JSON.Audit
           ((Plan => Plan, Approved => False, History => History), Signing_Seed => [1 .. 64 => '0']));
      Add (Improve.JSON.Publication ("PLAN-1", (others => <>), False));
      Add
        (Improve.JSON.Verification
           ((Plan_Id => Null_Unbounded_String, Baseline_Run | Verification_Run => 1, others => <>)));
      Add (Improve.JSON.Tasks (Empty_Tasks, "all"));
      Add (Improve.JSON.Status (Empty_Status));
      Add (Improve.JSON.Recovery ((others => <>)));
      Add (Improve.JSON.Error ("IMP-E-TEST", "internal_failure", "test"));
      Add (Improve.JSON.Error ("IMP-E-CANCELLED", "cancelled", "interrupted"));
      declare
         Original : constant String :=
           Improve.JSON.Audit ((Plan => Plan, Approved => False, History => History));
         Marker   : constant String := """approved"":false";
         Position : constant Natural := Ada.Strings.Fixed.Index (Original, Marker);
         Rejected : Boolean := False;
      begin
         declare
            Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
              Improve.Audit_Artifacts.Verify (Original);
            pragma Unreferenced (Mode);
         begin
            null;
         end;
         Assert (Position > 0, "audit integrity fixture has no approval field");
         begin
            declare
               Mode : constant Improve.Audit_Artifacts.Verification_Mode :=
                 Improve.Audit_Artifacts.Verify
                   (Original (Original'First .. Position - 1) & """approved"":true" &
                    Original (Position + Marker'Length .. Original'Last));
               pragma Unreferenced (Mode);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "audit verification accepted altered exported evidence");
         Check_Audit_Contract_Parity (Original);
      end;
      for Index in Documents.First_Index .. Documents.Last_Index loop
         declare
            Problem : constant String :=
              Improve_JSON_Schema_Testing.Validate
                (Schema_Directory, "improve-output-v2.schema.json", To_String (Documents (Index)));
         begin
            Assert (Problem = "", "JSON Schema document" & Positive'Image (Index) & " failed: " & Problem);
         end;
      end loop;
   end Check_All;
end Improve_JSON_Output_Testing;
