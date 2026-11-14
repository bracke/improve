--  Read publication mappings through the canonical joined-history decoder.
separate (Improve.Storage)
function Publications
  (Item       : in out Store;
   Plan_Id    : String := "";
   Maximum    : Positive := Default_Query_Maximum;
   Limits     : Read_Limits := Default_Read_Limits) return Publication_Vectors.Vector is
   Result : Publication_Vectors.Vector;

   procedure Append_Plan (Id : String; Revision : Positive) is
      Remaining : constant Natural := Maximum - Natural (Result.Length);
      Snapshot  : Inspection_History;
   begin
      if Remaining = 0 then
         raise Data_Error with "publication query exceeds configured item limit";
      end if;
      Snapshot := History (Item, Id, Revision, Positive (Remaining), Limits);
      Result.Append_Vector (Snapshot.Publications);
   end Append_Plan;
begin
   if Plan_Id /= "" then
      return History (Item, Plan_Id, Maximum => Maximum, Limits => Limits).Publications;
   end if;
   for Summary of List_All (Item, Limits.Maximum_History, Limits) loop
      Append_Plan (To_String (Summary.Plan_Id), Summary.Revision);
   end loop;
   return Result;
end Publications;
