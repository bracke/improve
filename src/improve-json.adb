with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Improve.JSON is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;

   LF : constant Character := Character'Val (10);

   function Lower (Text : String) return String is (Ada.Characters.Handling.To_Lower (Text));

   function Projects
     (Values      : Ada_Quality.Reporting.Project_Vectors.Vector;
      Snapshot_Id : String) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("projects"));
      Doc.Insert (Data, "snapshot", Doc.New_String (Snapshot_Id));
      for Value of Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "id", Doc.New_Integer (Long_Long_Integer (Value.Id)));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Value.Path)));
            Doc.Insert (Item, "enabled", Doc.New_Boolean (Value.Enabled));
            Doc.Insert (Item, "removed", Doc.New_Boolean (Value.Removed));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "projects", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Projects;

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("findings"));
      Doc.Insert (Data, "project_id", Doc.New_Integer (Long_Long_Integer (Selected.Project.Id)));
      Doc.Insert (Data, "project", Doc.New_String (To_String (Selected.Project.Name)));
      Doc.Insert (Data, "run_id", Doc.New_Integer (Long_Long_Integer (Selected.Assessment.Run.Id)));
      Doc.Insert (Data, "snapshot", Doc.New_String (To_String (Selected.Baseline.Snapshot_Id)));
      for Value of Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "indicator", Doc.New_String (Ada_Quality.Types.Image (Value.Indicator)));
            Doc.Insert (Item, "rule", Doc.New_String (To_String (Value.Rule)));
            Doc.Insert
              (Item, "severity", Doc.New_String (Lower (Ada_Quality.Types.Severity'Image (Value.Level))));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Value.Relative_Path)));
            Doc.Insert (Item, "line", Doc.New_Integer (Long_Long_Integer (Value.Line)));
            Doc.Insert (Item, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
            Doc.Insert (Item, "subject", Doc.New_String (To_String (Value.Semantic_Subject)));
            Doc.Insert (Item, "message", Doc.New_String (To_String (Value.Message)));
            Doc.Insert (Item, "evidence", Doc.New_String (To_String (Value.Evidence)));
            Doc.Insert (Item, "candidate_kind", Doc.New_String (Improve.Model.Image (Value.Kind)));
            Doc.Insert (Item, "indicator_level", Doc.New_Boolean (Value.Indicator_Level));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "findings", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Findings;

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String is
      Doc   : Document;
      Root  : constant Node := Doc.New_Object;
      Data  : constant Node := Doc.New_Object;
      Tasks : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("plan"));
      Doc.Insert (Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Data, "revision", Doc.New_Integer (Long_Long_Integer (Value.Revision)));
      Doc.Insert (Data, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project.Id)));
      Doc.Insert (Data, "project", Doc.New_String (To_String (Value.Project.Name)));
      Doc.Insert (Data, "run_id", Doc.New_Integer (Long_Long_Integer (Value.Baseline.Run_Id)));
      Doc.Insert (Data, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
      Doc.Insert (Data, "planner", Doc.New_String (To_String (Value.Planner_Id)));
      Doc.Insert (Data, "dry_run", Doc.New_Boolean (Dry_Run));
      Doc.Insert (Data, "stored", Doc.New_Boolean (not Dry_Run));
      for Spec of Value.Tasks loop
         declare
            Item         : constant Node := Doc.New_Object;
            Files        : constant Node := Doc.New_Array;
            Findings     : constant Node := Doc.New_Array;
            Dependencies : constant Node := Doc.New_Array;
         begin
            Doc.Insert (Item, "id", Doc.New_String (To_String (Spec.Id)));
            Doc.Insert (Item, "title", Doc.New_String (To_String (Spec.Title)));
            Doc.Insert (Item, "category", Doc.New_String (To_String (Spec.Category)));
            Doc.Insert (Item, "priority", Doc.New_String (Improve.Model.Image (Spec.Task_Priority)));
            Doc.Insert (Item, "candidate_kind", Doc.New_String (Improve.Model.Image (Spec.Kind)));
            Doc.Insert (Item, "goal", Doc.New_String (To_String (Spec.Goal)));
            Doc.Insert (Item, "problem", Doc.New_String (To_String (Spec.Problem)));
            Doc.Insert (Item, "evidence", Doc.New_String (To_String (Spec.Evidence)));
            Doc.Insert (Item, "scope", Doc.New_String (To_String (Spec.Scope)));
            Doc.Insert (Item, "out_of_scope", Doc.New_String (To_String (Spec.Out_Of_Scope)));
            Doc.Insert (Item, "requirements", Doc.New_String (To_String (Spec.Requirements)));
            Doc.Insert (Item, "acceptance", Doc.New_String (To_String (Spec.Acceptance)));
            Doc.Insert (Item, "verification", Doc.New_String (To_String (Spec.Verification)));
            Doc.Insert (Item, "confidence", Doc.New_Integer (Long_Long_Integer (Spec.Confidence)));
            Doc.Insert (Item, "requires_review", Doc.New_Boolean (Spec.Requires_Review));
            for File of Spec.Relevant_Files loop Doc.Append (Files, Doc.New_String (To_String (File))); end loop;
            for Key of Spec.Finding_Keys loop Doc.Append (Findings, Doc.New_String (To_String (Key))); end loop;
            for Dependency of Spec.Dependencies loop
               Doc.Append (Dependencies, Doc.New_String (To_String (Dependency)));
            end loop;
            Doc.Insert (Item, "files", Files);
            Doc.Insert (Item, "findings", Findings);
            Doc.Insert (Item, "depends_on", Dependencies);
            Doc.Append (Tasks, Item);
         end;
      end loop;
      Doc.Insert (Data, "tasks", Tasks);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Plan;

   function Plans (Values : Improve.Storage.Summary_Vectors.Vector) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("plan list"));
      for Value of Values loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
            Doc.Insert (Item, "revision", Doc.New_Integer (Long_Long_Integer (Value.Revision)));
            Doc.Insert (Item, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project_Id)));
            Doc.Insert (Item, "project", Doc.New_String (To_String (Value.Project)));
            Doc.Insert (Item, "run_id", Doc.New_Integer (Long_Long_Integer (Value.Run_Id)));
            Doc.Insert (Item, "task_count", Doc.New_Integer (Long_Long_Integer (Value.Task_Count)));
            Doc.Insert (Item, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "plans", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Plans;

   function Publication
     (Plan_Id : String; Value : Improve.Workflow.Publication_Result; Dry_Run : Boolean) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("apply"));
      Doc.Insert (Data, "plan_id", Doc.New_String (Plan_Id));
      Doc.Insert (Data, "task_kind", Doc.New_String (To_String (Value.Task_Kind)));
      Doc.Insert (Data, "dry_run", Doc.New_Boolean (Dry_Run));
      for Published of Value.Tasks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "improve_task_id", Doc.New_String (To_String (Published.Improve_Id)));
            Doc.Insert (Item, "harness_task_id", Doc.New_String (To_String (Published.Harness_Id)));
            Doc.Insert (Item, "origin", Doc.New_String (To_String (Published.Origin)));
            Doc.Insert (Item, "state", Doc.New_String (To_String (Published.State)));
            Doc.Insert (Item, "recovered", Doc.New_Boolean (Published.Recovered));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "tasks", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Publication;
end Improve.JSON;

