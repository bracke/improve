separate (Improve.Storage)
function Latest_Revision_Id
  (Item     : in out Store;
   Tx       : in out Database.Transactions.Transaction;
   Plan_Row : Positive;
   Budget   : in out History_Budget) return Natural is
   Result    : Natural := 0;
   Revisions : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Plan_Row);
begin
   while Entity_Tables.Has_Element (Revisions) loop
      Consume_History (Budget, "plan revision history");
      Result := Natural'Max (Result, Entity_Tables.Element (Revisions).Id);
      Advance_Children (Item, Tx, Revisions_Table, Plan_Row, Revisions);
   end loop;
   return Result;
end Latest_Revision_Id;
