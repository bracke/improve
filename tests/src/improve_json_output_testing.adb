with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with Improve.JSON;
with Improve.Presentation;
with Improve.State;
with Improve.Tasks;
with Improve_JSON_Schema_Testing;
with Project_Tools.Files;

package body Improve_JSON_Output_Testing is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;

   procedure Check_All (Plan : Improve.Model.Plan_Revision) is
      Schema_Directory : constant String :=
        (if Project_Tools.Files.File_Exists ("schemas/improve-output-v1.schema.json")
         then "schemas" else "../schemas");
      Schema : constant String :=
        Project_Tools.Files.Read_Raw_File (Schema_Directory & "/improve-output-v1.schema.json");
      Documents : Improve.Model.UString_Vectors.Vector;
      Empty_Plans : Improve.State.Summary_Vectors.Vector;
      Empty_Tasks : Improve.Tasks.View_Vectors.Vector;
      Empty_Status : Improve.Tasks.Status_Vectors.Vector;
      Empty_Findings : Improve.Model.Finding_Vectors.Vector;
      Empty_History : constant Improve.State.Inspection_History :=
        (Selected_Revision => 1, Publications => <>, Verifications => <>);
      procedure Add (Text : String) is
      begin
         Documents.Append (To_Unbounded_String (Text));
      end Add;
   begin
      Assert
        (Ada.Strings.Fixed.Index (Schema, """command"": { ""const"": ""audit""") > 0 and then
         Ada.Strings.Fixed.Index (Schema, """command"": { ""const"": ""error""") > 0 and then
         Ada.Strings.Fixed.Index (Schema, """additionalProperties"": false") > 0,
         "command-specific JSON schema branches are incomplete");
      Assert
        (Ada.Strings.Fixed.Index (Improve.Presentation.Plan_Graph (Plan), "digraph improve_plan") = 1,
         "DOT graph rendering failed");
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
      Add (Improve.JSON.Audit ((Plan => Plan, Approved => False, History => Empty_History)));
      Add (Improve.JSON.Publication ("PLAN-1", (others => <>), False));
      Add
        (Improve.JSON.Verification
           ((Plan_Id => Null_Unbounded_String, Baseline_Run | Verification_Run => 1, others => <>)));
      Add (Improve.JSON.Tasks (Empty_Tasks, "all"));
      Add (Improve.JSON.Status (Empty_Status));
      Add (Improve.JSON.Recovery ((others => <>)));
      Add (Improve.JSON.Error ("IMP-E-TEST", "internal_failure", "test"));
      for Index in Documents.First_Index .. Documents.Last_Index loop
         declare
            Problem : constant String :=
              Improve_JSON_Schema_Testing.Validate
                (Schema_Directory, "improve-output-v1.schema.json", To_String (Documents (Index)));
         begin
            Assert (Problem = "", "JSON Schema document" & Positive'Image (Index) & " failed: " & Problem);
         end;
      end loop;
   end Check_All;
end Improve_JSON_Output_Testing;
