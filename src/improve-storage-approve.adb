separate (Improve.Storage)
procedure Approve
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Read_Limits := Default_Read_Limits) is
   Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
   Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for plan approval";
   end if;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
              Field_Or (Payload, "fingerprint", "") = To_String (Plan.Fingerprint)
            then
               Database.Transactions.Rollback (Tx);
               return;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
      end loop;
   end;
   Row_Id := Next_Id (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, 0, WW (Key), WW ("approved"),
          WW (Pair ("plan_id", Plan_Id) & LF &
              Pair ("revision", Number (Revision)) & LF &
              Pair ("fingerprint", To_String (Plan.Fingerprint))), True, Operations_Table)),
      "record plan approval");
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Approve;
