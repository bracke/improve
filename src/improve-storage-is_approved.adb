separate (Improve.Storage)
function Is_Approved
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Read_Limits := Default_Read_Limits) return Boolean is
   Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
   Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
   Tx     : Database.Transactions.Transaction;
   Result : Boolean := False;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
              Field_Or (Payload, "fingerprint", "") = To_String (Plan.Fingerprint)
            then
               Result := True;
               exit;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
      end loop;
   end;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Is_Approved;
