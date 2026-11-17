separate (Improve.Storage)
procedure Migrate_To_Version_4
  (Item     : in out Store;
   Metadata : in out Entity;
   Limits   : Persistence_Limits) is
   Tx      : Database.Transactions.Transaction;
   Scanned : Natural := 0;
begin
   Begin_Write_Transaction (Item.DB, Tx);
   Improve.Storage.Allocation.Begin_Transaction (Item);
   declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
      while Entity_Tables.Has_Element (Tasks) loop
         if Scanned >= Limits.Maximum_Migration_Rows then
            raise Data_Error with "schema migration exceeds configured row limit";
         end if;
         Scanned := Scanned + 1;
         declare
            Row     : constant Entity := Entity_Tables.Element (Tasks);
            Payload : constant String := S (Row.Payload);
         begin
            if Payload'Length > Limits.Maximum_Text_Bytes then
               raise Data_Error with "legacy task payload exceeds configured persisted-text limit";
            end if;
            declare Task_Id : constant String := Field_Or (Payload, "draft_id", ""); begin
               if Task_Id /= "" then
                  Check
                    (Entity_Tables.Insert
                       (Tx, Item.DB, Item.Schemas (Task_Identities_Table),
                        (Improve.Storage.Allocation.Next (Item, Tx, Task_Identities_Table), Row.Parent_Id,
                         WW (Task_Id), WW ("active"), WW (Pair ("task_row", Number (Row.Id))),
                         True, Task_Identities_Table)),
                     "backfill task identity");
               end if;
            end;
         end;
         Advance (Item, Tx, Tasks_Table, Tasks);
      end loop;
   end;
   Metadata.State := WW ("4");
   Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "migrate task identity index");
   Improve.Storage.Allocation.Flush (Item, Tx);
   Commit_Transaction (Tx, "commit schema version 4 migration");
end Migrate_To_Version_4;
