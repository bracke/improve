separate (Improve.JSON)
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
