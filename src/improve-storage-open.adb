separate (Improve.Storage)
procedure Open
  (Item     : in out Store;
   Path     : String;
   Writable : Boolean;
   Limits   : Read_Limits := Default_Read_Limits) is
   Exists : constant Boolean := Ada.Directories.Exists (Path);
begin
   if Item.Opened then Close (Item); end if;
   if Writable then
      if Exists then Database.Open (Item.DB, Encode (Path)); else Database.Create (Item.DB, Encode (Path)); end if;
   else
      if not Exists then raise Dependency_Error with "Improve state database not found: " & Path; end if;
      Database.Open_Read_Only (Item.DB, Encode (Path));
   end if;
   if not Database.Last_Operation_Succeeded (Item.DB) then
      raise Dependency_Error with
        "cannot open Improve state: " & Decode (To_Wide_Wide_String (Database.Last_Result (Item.DB).Message));
   end if;
   Item.Opened := True;
   Item.Writable := Writable;
   Item.Schema_Version := 0;
   Item.Store_Id := Null_Unbounded_String;
   Item.Next_Ids := [others => 0];
   Item.Schemas (1) := New_Schema ("improve_records");
   if Writable then Check (Entity_Tables.Register (Item.DB, Item.Schemas (1)), "register Improve table"); end if;
   for Table in 2 .. Logical_Table_Count loop Item.Schemas (Table) := Item.Schemas (1); end loop;
   declare
      Tx       : Database.Transactions.Transaction;
      Metadata : Entity;
      Status   : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
         Physical_Key (Schema_Metadata_Table, 1), Metadata);
      Database.Transactions.Rollback (Tx);
      if Status.Code = Database.Status.Not_Found and then Writable and then not Exists then
         declare
            Store_Id : constant String := Decode
              (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
         begin
            Database.Transactions.Begin_Write (Item.DB, Tx);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
                  (1, 0, WW ("schema"), WW (Number (Current_Schema_Version)),
                   WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List & LF &
                       Pair ("store_id", Store_Id)), True, Schema_Metadata_Table)),
               "initialize schema metadata");
            Database.Transactions.Commit (Tx);
            Item.Schema_Version := Current_Schema_Version;
            Item.Store_Id := To_Unbounded_String (Store_Id);
         end;
      elsif not Database.Status.Is_Ok (Status) then
         raise Data_Error with "Improve schema metadata is missing or unreadable";
      else
         begin
            Item.Schema_Version := Natural'Value (S (Metadata.State));
         exception
            when Constraint_Error =>
               raise Data_Error with "unsupported Improve schema version " & S (Metadata.State);
         end;
         if Item.Schema_Version not in 1 .. Current_Schema_Version then
            raise Data_Error with "unsupported Improve schema version " & S (Metadata.State);
         elsif Item.Schema_Version < 3 and then Writable then
            Migrate_To_Version_3 (Item, Metadata);
            Item.Schema_Version := 3;
         end if;
         if Item.Schema_Version < 4 and then Writable then
            Migrate_To_Version_4 (Item, Metadata);
            Item.Schema_Version := 4;
         end if;
         if Item.Schema_Version < 5 and then Writable then
            Migrate_To_Version_5 (Item, Metadata, Limits);
            Item.Schema_Version := 5;
         end if;
         if Item.Schema_Version < 6 and then Writable then
            Migrate_To_Version_6 (Item, Metadata);
            Item.Schema_Version := 6;
         end if;
         if Item.Schema_Version >= 6 then
            Item.Store_Id := To_Unbounded_String (Field (S (Metadata.Payload), "store_id"));
            if Length (Item.Store_Id) = 0 then
               raise Data_Error with "Improve state-store identity is missing";
            end if;
         end if;
      end if;
   end;
exception
   when others =>
      if Database.Is_Open (Item.DB) then Database.Close (Item.DB); end if;
      Item.Opened := False;
      raise;
end Open;
