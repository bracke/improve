separate (Improve.Storage)
procedure Migrate_To_Version_3
  (Item     : in out Store;
   Metadata : in out Entity) is
   package Entity_Vectors is new Ada.Containers.Vectors (Positive, Entity);
   Tx      : Database.Transactions.Transaction;
   Pending : Entity_Vectors.Vector;

   procedure Backfill_Parents (Table : Positive) is
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Table);
   begin
      Pending.Clear;
      while Entity_Tables.Has_Element (Cursor) loop
         declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
            if Row.Parent_Id = 0 then Pending.Append (Row); end if;
         end;
         Advance (Item, Tx, Table, Cursor);
      end loop;
      for Row of Pending loop
         declare Updated : Entity := Row; begin
            Updated.Parent_Id := Plan_Row_Id (Field (S (Row.Payload), "plan_id"));
            Check
              (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Updated),
               "backfill indexed plan relationship");
         end;
      end loop;
   end Backfill_Parents;
begin
   Database.Transactions.Begin_Write (Item.DB, Tx);
   Backfill_Parents (Publications_Table);
   Backfill_Parents (Verifications_Table);
   Metadata.State := WW ("3");
   Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "migrate Improve schema metadata");
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Migrate_To_Version_3;
