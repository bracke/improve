--  Add a persistent state-store identity independent of its filesystem path.
separate (Improve.Storage)
procedure Migrate_To_Version_6
  (Item     : in out Store;
   Metadata : in out Entity) is
   Tx       : Database.Transactions.Transaction;
   Store_Id : constant String := Decode
     (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
begin
   Database.Transactions.Begin_Write (Item.DB, Tx);
   Metadata.State := WW ("6");
   Metadata.Payload := WW
     (S (Metadata.Payload) & LF & Pair ("store_id", Store_Id));
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "add persistent state-store identity");
   Database.Transactions.Commit (Tx);
   Item.Store_Id := To_Unbounded_String (Store_Id);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Migrate_To_Version_6;
