separate (Improve.Storage)
function List_All
  (Item    : in out Store;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Summary_Vectors.Vector is
   Result : Summary_Vectors.Vector;
   Tx : Database.Transactions.Transaction;
   Plans : Entity_Tables.Cursor;
   Scanned : Natural := 0;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   Plans := Scan (Item, Tx, Plans_Table);
   while Entity_Tables.Has_Element (Plans) loop
      if Scanned >= Limits.Maximum_History then
         raise Data_Error with "plan query exceeds configured history limit";
      end if;
      Scanned := Scanned + 1;
      declare
         Row    : constant Entity := Entity_Tables.Element (Plans);
         Latest : constant Natural :=
           Latest_Revision_Id (Item, Tx, Row.Id, Limits.Maximum_History, Scanned);
      begin
         if Latest > 0 then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "plan query exceeds configured item limit";
            end if;
            Result.Append (Summary_Of (Item, Tx, Positive (Latest), Limits));
         end if;
      end;
      Advance (Item, Tx, Plans_Table, Plans);
   end loop;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end List_All;
