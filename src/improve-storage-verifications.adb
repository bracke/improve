--  Read verification evidence through the canonical joined-history decoder.
separate (Improve.Storage)
function Verifications
  (Item    : in out Store;
   Plan_Id : String := "";
   Task_Id : String := "";
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Verification_Vectors.Vector is
   Result : Verification_Vectors.Vector;
   use type Improve.Model.Verification_Scope;

   procedure Append_Plan (Id : String; Revision : Natural) is
      Snapshot : constant Inspection_History :=
        History (Item, Id, Revision, Limits.Maximum_History, Limits);
   begin
      for Evidence of Snapshot.Verifications loop
         if Task_Id = "" or else
           (Evidence.Scope = Improve.Model.Task_Evaluation and then To_String (Evidence.Task_Id) = Task_Id)
         then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "verification query exceeds configured item limit";
            end if;
            Result.Append (Evidence);
         end if;
      end loop;
   end Append_Plan;
begin
   if Plan_Id /= "" then
      Append_Plan (Plan_Id, 0);
   else
      for Summary of List_All (Item, Limits.Maximum_History, Limits) loop
         Append_Plan (To_String (Summary.Plan_Id), Summary.Revision);
      end loop;
   end if;
   return Result;
end Verifications;
