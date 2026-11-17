--  Add transactionally updated logical identity counters.
separate (Improve.Storage)
procedure Migrate_To_Version_7
  (Item     : in out Store;
   Metadata : in out Entity;
   Limits   : Persistence_Limits) is
   Tx      : Database.Transactions.Transaction;
   Scanned : Natural := 0;
begin
   Begin_Write_Transaction (Item.DB, Tx);
   for Table in 2 .. Logical_Table_Count loop
      declare
         Cursor  : Entity_Tables.Cursor := Scan (Item, Tx, Table);
         Highest : Natural := 0;
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if Scanned >= Limits.Maximum_Migration_Rows then
               raise Data_Error with "identity-counter migration exceeds configured row limit";
            end if;
            Scanned := Scanned + 1;
            Highest := Natural'Max (Highest, Entity_Tables.Element (Cursor).Id);
            Advance (Item, Tx, Table, Cursor);
         end loop;
         if Highest >= Maximum_Logical_Id then
            raise Data_Error with "Improve logical identity space is exhausted";
         end if;
         Check
           (Entity_Tables.Insert
              (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
               (Table, 0, WW ("id_counter"), WW (Number (Highest + 1)),
                WW (Pair ("logical_table", Number (Table))), True, Schema_Metadata_Table)),
            "create logical identity counter");
      end;
   end loop;
   Metadata.State := WW (Number (Current_Schema_Version));
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "record schema version 7");
   Commit_Transaction (Tx, "commit schema version 7 migration");
end Migrate_To_Version_7;
