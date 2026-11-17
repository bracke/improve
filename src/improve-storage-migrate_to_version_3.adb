separate (Improve.Storage)
procedure Migrate_To_Version_3
  (Item     : in out Store;
   Metadata : in out Entity;
   Limits   : Persistence_Limits) is
   package Id_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   Tx      : Database.Transactions.Transaction;
   Pending : Id_Vectors.Vector;
   Scanned : Natural := 0;

   procedure Backfill_Parents (Table : Positive) is
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Table);
   begin
      Pending.Clear;
      while Entity_Tables.Has_Element (Cursor) loop
         if Scanned >= Limits.Maximum_Migration_Rows then
            raise Data_Error with "schema migration exceeds configured row limit";
         end if;
         Scanned := Scanned + 1;
         declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
            if Row.Parent_Id = 0 then
               declare Payload : constant String := S (Row.Payload); begin
                  if Payload'Length > Limits.Maximum_Text_Bytes then
                     raise Data_Error with "legacy history payload exceeds configured persisted-text limit";
                  end if;
                  Pending.Append (Row.Id);
               end;
            end if;
         end;
         Advance (Item, Tx, Table, Cursor);
      end loop;
      for Id of Pending loop
         declare
            Updated : Entity;
            Status  : constant Database.Status.Result :=
              Entity_Tables.Find
                (Tx, Item.DB, Item.Schemas (Table), Physical_Key (Table, Id), Updated);
         begin
            Check (Status, "reload legacy history row");
            Updated.Parent_Id := Plan_Row_Id (Field (S (Updated.Payload), "plan_id"));
            Check
              (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Updated),
               "backfill indexed plan relationship");
         end;
      end loop;
   end Backfill_Parents;
begin
   Begin_Write_Transaction (Item.DB, Tx);
   Backfill_Parents (Publications_Table);
   Backfill_Parents (Verifications_Table);
   Metadata.State := WW ("3");
   Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "migrate Improve schema metadata");
   Commit_Transaction (Tx, "commit schema version 3 migration");
end Migrate_To_Version_3;
