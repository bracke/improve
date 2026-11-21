with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Improve.Audit_Artifacts;
with Improve.Harness_States;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Improve.JSON is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;
   use type Improve.Tasks.Verification_Freshness;

   LF : constant Character := Character'Val (10);

   type Envelope is record
      Root : Node;
      Data : Node;
   end record;

   function Start_Envelope (Doc : in out Document; Command : String) return Envelope is
      Result : constant Envelope := (Root => Doc.New_Object, Data => Doc.New_Object);
   begin
      Doc.Insert (Result.Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Result.Root, "command", Doc.New_String (Command));
      return Result;
   end Start_Envelope;

   function Finish_Envelope
     (Doc   : in out Document;
      Value : Envelope) return String is
   begin
      Doc.Insert (Value.Root, "data", Value.Data);
      Doc.Set_Root (Value.Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Finish_Envelope;

   function Audit_Envelope_Overhead return Natural is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "audit");
      Text    : constant String := Finish_Envelope (Doc, Context);
   begin
      return Text'Length - 2;
   end Audit_Envelope_Overhead;

   function Integrity_Skeleton_Length (Signed : Boolean) return Natural is
      Doc  : Document;
      Data : constant Node := Doc.New_Object;
      Text : Unbounded_String;
   begin
      Doc.Insert (Data, "canonical_payload", Doc.New_String (""));
      Doc.Insert (Data, "bundle_digest", Doc.New_String (""));
      if Signed then
         Doc.Insert (Data, "public_key", Doc.New_String (""));
         Doc.Insert (Data, "signature", Doc.New_String (""));
      end if;
      Text := To_Unbounded_String (Jsonlib.Serializers.To_String (Doc, Data));
      return Length (Text) - 2;
   end Integrity_Skeleton_Length;

   function Text (Command, Kind, Value : String) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, Command);
   begin
      Doc.Insert (Context.Data, "kind", Doc.New_String (Kind));
      Doc.Insert (Context.Data, "text", Doc.New_String (Value));
      return Finish_Envelope (Doc, Context);
   end Text;

   function Lower (Text : String) return String is (Ada.Characters.Handling.To_Lower (Text));

   function Projects (Value : Improve.Results.Project_List) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "projects");
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "snapshot", Doc.New_String (To_String (Value.Snapshot)));
      for Project of Value.Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "id", Doc.New_Integer (Long_Long_Integer (Project.Id)));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Project.Path)));
            Doc.Insert (Item, "enabled", Doc.New_Boolean (Project.Enabled));
            Doc.Insert (Item, "removed", Doc.New_Boolean (Project.Removed));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "projects", List);
      return Finish_Envelope (Doc, Context);
   end Projects;

   function Findings (Value : Improve.Results.Finding_List; Next_Cursor : String := "") return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "findings");
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project_Id)));
      Doc.Insert (Data, "project", Doc.New_String (To_String (Value.Project)));
      Doc.Insert (Data, "run_id", Doc.New_Integer (Long_Long_Integer (Value.Run_Id)));
      Doc.Insert (Data, "assessment", Doc.New_String (To_String (Value.Assessment_Id)));
      Doc.Insert (Data, "snapshot", Doc.New_String (To_String (Value.Snapshot_Id)));
      for Finding of Value.Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "indicator", Doc.New_String (Ada_Quality.Types.Image (Finding.Indicator)));
            Doc.Insert (Item, "rule", Doc.New_String (To_String (Finding.Rule)));
            Doc.Insert
              (Item, "severity", Doc.New_String (Lower (Ada_Quality.Types.Severity'Image (Finding.Level))));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Finding.Relative_Path)));
            Doc.Insert (Item, "line", Doc.New_Integer (Long_Long_Integer (Finding.Line)));
            Doc.Insert (Item, "fingerprint", Doc.New_String (To_String (Finding.Fingerprint)));
            Doc.Insert (Item, "subject", Doc.New_String (To_String (Finding.Semantic_Subject)));
            Doc.Insert (Item, "message", Doc.New_String (To_String (Finding.Message)));
            Doc.Insert (Item, "evidence", Doc.New_String (To_String (Finding.Evidence)));
            Doc.Insert (Item, "candidate_kind", Doc.New_String (Improve.Model.Image (Finding.Kind)));
            Doc.Insert (Item, "indicator_level", Doc.New_Boolean (Finding.Indicator_Level));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "findings", List);
      if Next_Cursor /= "" then Doc.Insert (Data, "next_cursor", Doc.New_String (Next_Cursor)); end if;
      return Finish_Envelope (Doc, Context);
   end Findings;

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String is separate;

   function Plan_Graph (Value : Improve.Model.Plan_Revision) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "plan graph");
      Nodes   : constant Node := Doc.New_Array;
      Edges   : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Context.Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Context.Data, "revision", Doc.New_Integer (Long_Long_Integer (Value.Revision)));
      for Spec of Value.Tasks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "id", Doc.New_String (To_String (Spec.Id)));
            Doc.Insert (Item, "title", Doc.New_String (To_String (Spec.Title)));
            Doc.Insert (Item, "priority", Doc.New_String (Improve.Model.Image (Spec.Task_Priority)));
            Doc.Append (Nodes, Item);
         end;
         for Dependency of Spec.Dependencies loop
            declare Edge : constant Node := Doc.New_Object; begin
               Doc.Insert (Edge, "from", Doc.New_String (To_String (Dependency)));
               Doc.Insert (Edge, "to", Doc.New_String (To_String (Spec.Id)));
               Doc.Append (Edges, Edge);
            end;
         end loop;
      end loop;
      Doc.Insert (Context.Data, "nodes", Nodes);
      Doc.Insert (Context.Data, "edges", Edges);
      return Finish_Envelope (Doc, Context);
   end Plan_Graph;

   function Plans (Values : Improve.State.Summary_Vectors.Vector; Next_Cursor : String := "") return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "plan list");
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
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
      if Next_Cursor /= "" then Doc.Insert (Data, "next_cursor", Doc.New_String (Next_Cursor)); end if;
      return Finish_Envelope (Doc, Context);
   end Plans;

   function Plan_Approval (Value : Improve.Model.Plan_Revision) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "plan approve");
      Data    : Node renames Context.Data;
   begin
      Doc.Insert (Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Data, "revision", Doc.New_Integer (Long_Long_Integer (Value.Revision)));
      Doc.Insert (Data, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
      Doc.Insert (Data, "approved", Doc.New_Boolean (True));
      return Finish_Envelope (Doc, Context);
   end Plan_Approval;

   function Plan_Comparison (Value : Improve.Results.Plan_Comparison; Explain : Boolean) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, (if Explain then "plan explain" else "plan diff"));
      Reasons : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Context.Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert
        (Context.Data, "from_revision", Doc.New_Integer (Long_Long_Integer (Value.From_Revision)));
      Doc.Insert (Context.Data, "to_revision", Doc.New_Integer (Long_Long_Integer (Value.To_Revision)));
      Doc.Insert (Context.Data, "changed", Doc.New_Boolean (Value.Changed));
      for Reason of Value.Reasons loop Doc.Append (Reasons, Doc.New_String (To_String (Reason))); end loop;
      Doc.Insert (Context.Data, "reasons", Reasons);
      return Finish_Envelope (Doc, Context);
   end Plan_Comparison;

   function Diagnostics (Value : Improve.Results.Diagnostic_Report) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "doctor");
      Checks  : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Context.Data, "healthy", Doc.New_Boolean (Value.Healthy));
      for Check of Value.Checks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "name", Doc.New_String (To_String (Check.Name)));
            Doc.Insert
              (Item, "status",
               Doc.New_String
                 (case Check.Status is
                     when Improve.Results.Diagnostic_Pass => "pass",
                     when Improve.Results.Diagnostic_Warning => "warning",
                     when Improve.Results.Diagnostic_Fail => "fail"));
            Doc.Insert (Item, "detail", Doc.New_String (To_String (Check.Detail)));
            Doc.Append (Checks, Item);
         end;
      end loop;
      Doc.Insert (Context.Data, "checks", Checks);
      return Finish_Envelope (Doc, Context);
   end Diagnostics;

   function Audit
     (Value        : Improve.Results.Audit_Bundle;
      Next_Cursor  : String := "";
      Signing_Seed : String := "") return String is separate;

   function Error
     (Code, Category, Detail : String;
      Hint                   : String := "") return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "error");
   begin
      Doc.Insert (Context.Data, "code", Doc.New_String (Code));
      Doc.Insert (Context.Data, "category", Doc.New_String (Category));
      Doc.Insert (Context.Data, "detail", Doc.New_String (Detail));
      if Hint /= "" then Doc.Insert (Context.Data, "hint", Doc.New_String (Hint)); end if;
      return Finish_Envelope (Doc, Context);
   end Error;

   function Publication
     (Plan_Id : String; Value : Improve.Results.Publication_Result; Dry_Run : Boolean) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "apply");
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "plan_id", Doc.New_String (Plan_Id));
      Doc.Insert (Data, "task_kind", Doc.New_String (To_String (Value.Task_Kind)));
      Doc.Insert (Data, "dry_run", Doc.New_Boolean (Dry_Run));
      for Published of Value.Tasks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "improve_task_id", Doc.New_String (To_String (Published.Improve_Id)));
            Doc.Insert (Item, "harness_task_id", Doc.New_String (To_String (Published.Harness_Id)));
            Doc.Insert (Item, "origin", Doc.New_String (To_String (Published.Origin)));
            Doc.Insert (Item, "state", Doc.New_String (To_String (Published.State)));
            Doc.Insert (Item, "core_state", Doc.New_String (Improve.Harness_States.Image (Published.Core_State)));
            Doc.Insert (Item, "recovered", Doc.New_Boolean (Published.Recovered));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "tasks", List);
      return Finish_Envelope (Doc, Context);
   end Publication;

   function Verification
     (Value   : Improve.Results.Verification_Report;
      Command : String := "verify") return String is separate;

   procedure Append_Task
     (Doc    : in out Document;
      List   : Node;
      Value  : Improve.Tasks.Task_View) is
      Item : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Item, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project_Id)));
      Doc.Insert (Item, "project", Doc.New_String (To_String (Value.Project)));
      Doc.Insert (Item, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Item, "improve_task_id", Doc.New_String (To_String (Value.Improve_Id)));
      Doc.Insert (Item, "harness_task_id", Doc.New_String (To_String (Value.Harness_Id)));
      Doc.Insert (Item, "title", Doc.New_String (To_String (Value.Title)));
      Doc.Insert (Item, "harness_state", Doc.New_String (To_String (Value.Harness_State)));
      Doc.Insert
        (Item, "harness_core_state", Doc.New_String (Improve.Harness_States.Image (Value.Harness_Core_State)));
      Doc.Insert (Item, "quality_outcome", Doc.New_String (Improve.Model.Image (Value.Quality)));
      Doc.Insert (Item, "verification_run", Doc.New_Integer (Long_Long_Integer (Value.Verification_Run)));
      Doc.Insert (Item, "verification_freshness", Doc.New_String (Improve.Tasks.Image (Value.Freshness)));
      Doc.Insert
        (Item, "verification_current",
         Doc.New_Boolean (Value.Freshness = Improve.Tasks.Freshness_Current));
      Doc.Insert
        (Item, "status", Doc.New_String (Improve.Tasks.Image (Improve.Tasks.Status (Value))));
      Doc.Append (List, Item);
   end Append_Task;

   function Tasks
     (Values : Improve.Tasks.View_Vectors.Vector;
      Filter : String;
      Next_Cursor : String := "") return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "tasks");
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "filter", Doc.New_String (if Filter = "" then "all" else Filter));
      for Value of Values loop Append_Task (Doc, List, Value); end loop;
      Doc.Insert (Data, "tasks", List);
      if Next_Cursor /= "" then Doc.Insert (Data, "next_cursor", Doc.New_String (Next_Cursor)); end if;
      return Finish_Envelope (Doc, Context);
   end Tasks;

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String is separate;

   function Recovery (Value : Improve.Results.Recovery_Result) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "recover");
      Data    : Node renames Context.Data;
   begin
      Doc.Insert
        (Data, "operations_recovered", Doc.New_Integer (Long_Long_Integer (Value.Operations_Recovered)));
      Doc.Insert (Data, "tasks_recovered", Doc.New_Integer (Long_Long_Integer (Value.Tasks_Recovered)));
      return Finish_Envelope (Doc, Context);
   end Recovery;
end Improve.JSON;

