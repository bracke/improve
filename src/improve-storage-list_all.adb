separate (Improve.Storage)
function List_All
  (Item    : in out Store;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Persistence_Limits := Default_Persistence_Limits) return Summary_Vectors.Vector is
   Result : Summary_Vectors.Vector;
   Tx : Database.Transactions.Transaction;
   Plans : Entity_Tables.Cursor;
   Budget : History_Budget := New_History_Budget (Limits);
begin
   Begin_Read_Transaction (Item.DB, Tx);
   Plans := Scan (Item, Tx, Plans_Table);
   while Entity_Tables.Has_Element (Plans) loop
      Consume_History (Budget, "plan query history");
      declare
         Row    : constant Entity := Entity_Tables.Element (Plans);
         Latest : constant Natural :=
           Latest_Revision_Id (Item, Tx, Row.Id, Budget);
      begin
         if Latest > 0 then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "plan query exceeds configured item limit";
            end if;
            Result.Append (Summary_Of (Item, Tx, Positive (Latest), Limits).Value);
         end if;
      end;
      Advance (Item, Tx, Plans_Table, Plans);
   end loop;
   Rollback_Transaction (Tx, "finish all-plan query");
   return Result;
end List_All;
