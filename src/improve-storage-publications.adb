--  Read publication mappings from one consistent history snapshot.
separate (Improve.Storage)
function Publications
  (Item       : in out Store;
   Plan_Id    : String := "";
   Maximum    : Positive := Default_Query_Maximum;
   Limits     : Persistence_Limits := Default_Persistence_Limits) return Publication_Vectors.Vector is
   Result  : Publication_Vectors.Vector;
   Decoded : History_Support.Publication_Envelope_Lists.List;
   Tx      : Database.Transactions.Transaction;
   Budget  : History_Budget := New_History_Budget (Limits);
begin
   if Plan_Id /= "" then
      return History
        (Item, Plan_Id, Maximum => Maximum, Limits => Limits,
         Selection => Publication_History).Publications;
   end if;
   Begin_Read_Transaction (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "publication query history");
         declare
            Row      : constant Entity := Entity_Tables.Element (Cursor);
            Envelope : History_Support.Publication_Envelope;
         begin
            History_Support.Decode_Publication
              (Item, Row, Expected_Plan_Id => "", Limits => Limits,
               Value => Envelope);
            if Decoded.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "publication query exceeds configured item limit";
            end if;
            Decoded.Append (Envelope);
         end;
         Advance (Item, Tx, Publications_Table, Cursor);
      end loop;
   end;
   Rollback_Transaction (Tx, "finish publication query");
   History_Support.Validate_Publications (Item, Decoded, Limits, Budget);
   while not Decoded.Is_Empty loop
      Result.Append (Decoded.First_Element.Value);
      Decoded.Delete_First;
   end loop;
   return Result;
end Publications;
