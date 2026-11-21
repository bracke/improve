separate (Improve.JSON)
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
