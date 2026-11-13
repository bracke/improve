separate (Improve.Storage)
procedure Migrate_To_Version_4
  (Item     : in out Store;
   Metadata : in out Entity) is
   Tx : Database.Transactions.Transaction;
begin
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
      while Entity_Tables.Has_Element (Tasks) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Tasks);
            Payload : constant String := S (Row.Payload);
            Task_Id : constant String := Field_Or (Payload, "draft_id", "");
         begin
            if Task_Id /= "" then
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Task_Identities_Table),
                     (Next_Id (Item, Tx, Task_Identities_Table), Row.Parent_Id,
                      WW (Task_Id), WW ("active"), WW (Pair ("task_row", Number (Row.Id))),
                      True, Task_Identities_Table)),
                  "backfill task identity");
            end if;
         end;
         Advance (Item, Tx, Tasks_Table, Tasks);
      end loop;
   end;
   Metadata.State := WW ("4");
   Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "migrate task identity index");
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Migrate_To_Version_4;
