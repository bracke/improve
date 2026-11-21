separate (Improve.JSON)
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
      declare
         Item : constant Node := Doc.New_Object;
      begin
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
