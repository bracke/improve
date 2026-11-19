with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Improve.Audit_Artifacts;
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

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, "plan");
      Data    : Node renames Context.Data;
      Tasks   : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Data, "revision", Doc.New_Integer (Long_Long_Integer (Value.Revision)));
      Doc.Insert (Data, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project.Id)));
      Doc.Insert (Data, "project", Doc.New_String (To_String (Value.Project.Name)));
      Doc.Insert (Data, "run_id", Doc.New_Integer (Long_Long_Integer (Value.Baseline.Run_Id)));
      Doc.Insert (Data, "assessment_fingerprint", Doc.New_String (To_String (Value.Baseline.Evidence_Id)));
      Doc.Insert (Data, "working_source_fingerprint", Doc.New_String (To_String (Value.Working_Source_Id)));
      Doc.Insert (Data, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
      Doc.Insert (Data, "planner", Doc.New_String (To_String (Value.Planner_Id)));
      Doc.Insert (Data, "agent_provider", Doc.New_String (To_String (Value.Agent_Provider_Id)));
      Doc.Insert (Data, "agent_model_sha256", Doc.New_String (To_String (Value.Agent_Model_SHA256)));
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
      return Finish_Envelope (Doc, Context);
   end Plan;

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
      Signing_Seed : String := "") return String is
      Doc          : Document;
      Context      : constant Envelope := Start_Envelope (Doc, "audit");
      Publications : constant Node := Doc.New_Array;
      Verifications : constant Node := Doc.New_Array;
      Tasks        : constant Node := Doc.New_Array;
      Findings     : constant Node := Doc.New_Array;
      Plan         : Improve.Model.Plan_Revision renames Value.Plan;
   begin
      Doc.Insert (Context.Data, "plan_id", Doc.New_String (To_String (Plan.Plan_Id)));
      Doc.Insert (Context.Data, "revision", Doc.New_Integer (Long_Long_Integer (Plan.Revision)));
      Doc.Insert (Context.Data, "fingerprint", Doc.New_String (To_String (Plan.Fingerprint)));
      Doc.Insert (Context.Data, "approved", Doc.New_Boolean (Value.Approved));
      Doc.Insert (Context.Data, "project_id", Doc.New_Integer (Long_Long_Integer (Plan.Project.Id)));
      Doc.Insert (Context.Data, "project", Doc.New_String (To_String (Plan.Project.Name)));
      Doc.Insert (Context.Data, "database_id", Doc.New_String (To_String (Plan.Project.Database_Id)));
      Doc.Insert (Context.Data, "baseline_run", Doc.New_Integer (Long_Long_Integer (Plan.Baseline.Run_Id)));
      Doc.Insert (Context.Data, "source_id", Doc.New_String (To_String (Plan.Baseline.Source_Id)));
      Doc.Insert (Context.Data, "policy_id", Doc.New_String (To_String (Plan.Baseline.Policy_Id)));
      Doc.Insert (Context.Data, "toolchain_id", Doc.New_String (To_String (Plan.Baseline.Toolchain_Id)));
      Doc.Insert (Context.Data, "evidence_id", Doc.New_String (To_String (Plan.Baseline.Evidence_Id)));
      Doc.Insert (Context.Data, "planner_id", Doc.New_String (To_String (Plan.Planner_Id)));
      Doc.Insert
        (Context.Data, "agent_provider", Doc.New_String (To_String (Plan.Agent_Provider_Id)));
      Doc.Insert
        (Context.Data, "agent_model_sha256", Doc.New_String (To_String (Plan.Agent_Model_SHA256)));
      for Finding of Plan.Findings loop
         Doc.Append (Findings, Doc.New_String (Improve.Model.Finding_Key (Finding)));
      end loop;
      Doc.Insert (Context.Data, "finding_keys", Findings);
      for Spec of Plan.Tasks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "id", Doc.New_String (To_String (Spec.Id)));
            Doc.Insert (Item, "title", Doc.New_String (To_String (Spec.Title)));
            Doc.Insert
              (Item, "contract_fingerprint",
               Doc.New_String (Improve.Model.Task_Contract_Fingerprint (Spec)));
            Doc.Append (Tasks, Item);
         end;
      end loop;
      Doc.Insert (Context.Data, "tasks", Tasks);
      for History_Item of Value.History.Publications loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "improve_task_id", Doc.New_String (To_String (History_Item.Improve_Task_Id)));
            Doc.Insert (Item, "harness_task_id", Doc.New_String (To_String (History_Item.Harness_Task_Id)));
            Doc.Insert (Item, "origin", Doc.New_String (To_String (History_Item.Origin)));
            Doc.Insert (Item, "contract", Doc.New_String (To_String (History_Item.Contract)));
            Doc.Insert (Item, "state", Doc.New_String (To_String (History_Item.State)));
            Doc.Insert
              (Item, "plan_revision", Doc.New_Integer (Long_Long_Integer (History_Item.Plan_Revision)));
            Doc.Append (Publications, Item);
         end;
      end loop;
      Doc.Insert (Context.Data, "publications", Publications);
      for History_Item of Value.History.Verifications loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "scope", Doc.New_String (Improve.Model.Image (History_Item.Scope)));
            Doc.Insert (Item, "task_id", Doc.New_String (To_String (History_Item.Task_Id)));
            Doc.Insert
              (Item, "plan_revision", Doc.New_Integer (Long_Long_Integer (History_Item.Plan_Revision)));
            Doc.Insert
              (Item, "contract_fingerprint", Doc.New_String (To_String (History_Item.Contract_Fingerprint)));
            Doc.Insert
              (Item, "assessment_id", Doc.New_Integer (Long_Long_Integer (History_Item.Assessment_Id)));
            Doc.Insert (Item, "outcome", Doc.New_String (Improve.Model.Image (History_Item.Outcome)));
            Doc.Insert (Item, "comparable", Doc.New_Boolean (History_Item.Comparable));
            Doc.Insert (Item, "explanation", Doc.New_String (To_String (History_Item.Explanation)));
            Doc.Append (Verifications, Item);
         end;
      end loop;
      Doc.Insert (Context.Data, "verifications", Verifications);
      Doc.Insert
        (Context.Data, "canonical_payload", Doc.New_String (Improve.Audit_Artifacts.Canonical (Value)));
      Doc.Insert (Context.Data, "bundle_digest", Doc.New_String (Improve.Audit_Artifacts.Digest (Value)));
      if Signing_Seed /= "" then
         declare
            Public_Key : Unbounded_String;
            Signature  : Unbounded_String;
         begin
            Improve.Audit_Artifacts.Sign
              (Improve.Audit_Artifacts.Digest (Value), Signing_Seed, Public_Key, Signature);
            Doc.Insert (Context.Data, "public_key", Doc.New_String (To_String (Public_Key)));
            Doc.Insert (Context.Data, "signature", Doc.New_String (To_String (Signature)));
         end;
      end if;
      if Next_Cursor /= "" then Doc.Insert (Context.Data, "next_cursor", Doc.New_String (Next_Cursor)); end if;
      return Finish_Envelope (Doc, Context);
   end Audit;

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
            Doc.Insert (Item, "recovered", Doc.New_Boolean (Published.Recovered));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "tasks", List);
      return Finish_Envelope (Doc, Context);
   end Publication;

   function Verification
     (Value   : Improve.Results.Verification_Report;
      Command : String := "verify") return String is
      Doc     : Document;
      Context : constant Envelope := Start_Envelope (Doc, Command);
      Data    : Node renames Context.Data;
      List    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Data, "plan_id", Doc.New_String (To_String (Value.Plan_Id)));
      Doc.Insert (Data, "baseline_run", Doc.New_Integer (Long_Long_Integer (Value.Baseline_Run)));
      Doc.Insert (Data, "verification_run", Doc.New_Integer (Long_Long_Integer (Value.Verification_Run)));
      Doc.Insert (Data, "outcome", Doc.New_String (Improve.Model.Image (Value.Outcome)));
      Doc.Insert (Data, "plan_outcome", Doc.New_String (Improve.Model.Image (Value.Plan_Outcome)));
      Doc.Insert (Data, "project_outcome", Doc.New_String (Improve.Model.Image (Value.Project_Outcome)));
      Doc.Insert (Data, "comparable", Doc.New_Boolean (Value.Comparable));
      Doc.Insert (Data, "new_critical", Doc.New_Integer (Long_Long_Integer (Value.New_Critical)));
      Doc.Insert (Data, "explanation", Doc.New_String (To_String (Value.Explanation)));
      for Result of Value.Tasks loop
         declare Item : constant Node := Doc.New_Object; begin
            Doc.Insert (Item, "task_id", Doc.New_String (To_String (Result.Task_Id)));
            Doc.Insert (Item, "outcome", Doc.New_String (Improve.Model.Image (Result.Outcome)));
            Doc.Insert (Item, "matched", Doc.New_Integer (Long_Long_Integer (Result.Matched)));
            Doc.Insert (Item, "total", Doc.New_Integer (Long_Long_Integer (Result.Total)));
            Doc.Insert (Item, "explanation", Doc.New_String (To_String (Result.Explanation)));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "tasks", List);
      return Finish_Envelope (Doc, Context);
   end Verification;

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

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String is
      Doc      : Document;
      Context  : constant Envelope := Start_Envelope (Doc, "status");
      Data     : Node renames Context.Data;
      Projects : constant Node := Doc.New_Array;
   begin
      for Value of Values loop
         declare
            Item     : constant Node := Doc.New_Object;
            Tasks    : constant Node := Doc.New_Array;
            Findings : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "project_id", Doc.New_Integer (Long_Long_Integer (Value.Project_Id)));
            Doc.Insert (Item, "project", Doc.New_String (To_String (Value.Project)));
            Doc.Insert (Item, "baseline_run", Doc.New_Integer (Long_Long_Integer (Value.Baseline_Run)));
            Doc.Insert (Item, "latest_run", Doc.New_Integer (Long_Long_Integer (Value.Latest_Run)));
            Doc.Insert (Item, "plan_count", Doc.New_Integer (Long_Long_Integer (Value.Plan_Count)));
            Doc.Insert
              (Item, "plan_quality",
               Doc.New_String
                 (if Value.Has_Plan_Verification and then Value.Plan_Verification_Run = Value.Latest_Run
                  then Improve.Model.Image (Value.Plan_Quality)
                  else "unverified"));
            Doc.Insert
              (Item, "plan_verification_run",
               Doc.New_Integer (Long_Long_Integer (Value.Plan_Verification_Run)));
            Doc.Insert
              (Item, "plan_verification_current",
               Doc.New_Boolean
                 (Value.Has_Plan_Verification and then Value.Plan_Verification_Run = Value.Latest_Run));
            Doc.Insert
              (Item, "previous_plan_quality",
               Doc.New_String
                 (if Value.Has_Plan_Verification and then Value.Plan_Verification_Run /= Value.Latest_Run
                  then Improve.Model.Image (Value.Plan_Quality)
                  else "unverified"));
            Doc.Insert
              (Item, "project_quality",
               Doc.New_String
                 (if Value.Has_Project_Verification and then Value.Project_Verification_Run = Value.Latest_Run
                  then Improve.Model.Image (Value.Project_Quality)
                  else "unverified"));
            Doc.Insert
              (Item, "project_verification_run",
               Doc.New_Integer (Long_Long_Integer (Value.Project_Verification_Run)));
            Doc.Insert
              (Item, "project_verification_current",
               Doc.New_Boolean
                 (Value.Has_Project_Verification and then Value.Project_Verification_Run = Value.Latest_Run));
            Doc.Insert
              (Item, "previous_project_quality",
               Doc.New_String
                 (if Value.Has_Project_Verification and then Value.Project_Verification_Run /= Value.Latest_Run
                  then Improve.Model.Image (Value.Project_Quality)
                  else "unverified"));
            for View of Value.Tasks loop Append_Task (Doc, Tasks, View); end loop;
            Doc.Insert (Item, "tasks", Tasks);
            Doc.Insert (Findings, "resolved", Doc.New_Integer (Long_Long_Integer (Value.Findings.Resolved)));
            Doc.Insert
              (Findings, "outstanding", Doc.New_Integer (Long_Long_Integer (Value.Findings.Outstanding)));
            Doc.Insert
              (Findings, "not_measurable", Doc.New_Integer (Long_Long_Integer (Value.Findings.Not_Measurable)));
            Doc.Insert (Findings, "regressed", Doc.New_Integer (Long_Long_Integer (Value.Findings.Regressed)));
            Doc.Insert (Findings, "superseded", Doc.New_Integer (Long_Long_Integer (Value.Findings.Superseded)));
            Doc.Insert
              (Findings, "previously_resolved",
               Doc.New_Integer (Long_Long_Integer (Value.Findings.Previously_Resolved)));
            Doc.Insert (Findings, "unverified", Doc.New_Integer (Long_Long_Integer (Value.Findings.Unverified)));
            Doc.Insert (Item, "findings", Findings);
            Doc.Append (Projects, Item);
         end;
      end loop;
      Doc.Insert (Data, "projects", Projects);
      return Finish_Envelope (Doc, Context);
   end Status;

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

