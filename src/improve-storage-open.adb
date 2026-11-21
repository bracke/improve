separate (Improve.Storage)
procedure Open
  (Item     : in out Store;
   Path     : String;
   Writable : Boolean;
   Limits   : Persistence_Limits := Default_Persistence_Limits) is
   Exists  : constant Boolean := Ada.Directories.Exists (Path);
   Created : Boolean := False;

   procedure Remove_Created_Artifacts is
      Database_Path : constant Wide_Wide_String := Encode (Path);
      Full_Text_Path : constant Wide_Wide_String := Encode (Path & ".fts");
   begin
      if Database.WAL.Exists (Database_Path) then
         Check
           (Database.WAL.Delete (Database_Path),
            "remove incomplete Improve write-ahead log");
      end if;
      if Database.Storage.File_IO.File_Exists (Full_Text_Path) then
         Check
           (Database.Storage.File_IO.Delete_File (Full_Text_Path),
            "remove incomplete Improve full-text state");
      end if;
      if Database.Storage.File_IO.File_Exists (Database_Path) then
         Check
           (Database.Storage.File_IO.Delete_File (Database_Path),
            "remove incomplete Improve state");
      end if;
   end Remove_Created_Artifacts;
begin
   if Item.Opened then Close (Item); end if;
   if Writable then
      if Exists then
         Database.Open (Item.DB, Encode (Path));
      else
         Database.Create (Item.DB, Encode (Path));
         Created := Database.Last_Operation_Succeeded (Item.DB);
      end if;
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
   Item.Dirty_Ids := [others => False];
   Item.Schemas (1) := New_Schema ("improve_records");
   if Writable and then not Exists then
      Check (Entity_Tables.Register (Item.DB, Item.Schemas (1)), "register Improve table");
   end if;
   for Table in 2 .. Logical_Table_Count loop Item.Schemas (Table) := Item.Schemas (1); end loop;
   declare
      Tx       : Database.Transactions.Transaction;
      Metadata : Entity;
      Status   : Database.Status.Result;
   begin
      Begin_Read_Transaction (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
         Physical_Key (Schema_Metadata_Table, 1), Metadata);
      Rollback_Transaction (Tx, "finish schema metadata query");
      if Status.Code = Database.Status.Not_Found and then Writable and then not Exists then
         declare
            Store_Id : constant String := Decode
              (Database.UUIDs.UUID_To_String (Database.UUIDs.Generate_UUID));
         begin
            Begin_Write_Transaction (Item.DB, Tx);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
                  (1, 0, WW ("schema"), WW (Number (Current_Schema_Version)),
                   WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List & LF &
                       Pair ("store_id", Store_Id)), True, Schema_Metadata_Table)),
               "initialize schema metadata");
            for Table in 2 .. Logical_Table_Count loop
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
                     (Table, 0, WW ("id_counter"), WW ("1"),
                      WW (Pair ("logical_table", Number (Table))), True, Schema_Metadata_Table)),
                  "initialize logical identity counter");
            end loop;
            Commit_Transaction (Tx, "commit schema initialization");
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
         end if;
         declare
            Manifest : constant String := Field (S (Metadata.Payload), "logical_tables");
            Current  : constant String := Logical_Table_List;
            Known_Legacy_Prefix : constant Boolean :=
              Manifest'Length < Current'Length and then Manifest /= "" and then
              Current (Current'First .. Current'First + Manifest'Length - 1) = Manifest and then
              Current (Current'First + Manifest'Length) = ',';
         begin
            if Metadata.Parent_Id /= 0 or else S (Metadata.Kind) /= "schema" or else not Metadata.Active or else
              Field (S (Metadata.Payload), "created_by") /= "improve" or else
              (Manifest /= Current and then
               (Item.Schema_Version = Current_Schema_Version or else not Known_Legacy_Prefix))
            then
               raise Data_Error with "Improve state-store ownership metadata is invalid";
            end if;
         end;
         if Writable then
            Check (Entity_Tables.Register (Item.DB, Item.Schemas (1)), "validate Improve table");
         end if;
         if Item.Schema_Version < 3 and then Writable then
            Migrate_To_Version_3 (Item, Metadata, Limits);
            Item.Schema_Version := 3;
         end if;
         if Item.Schema_Version < 4 and then Writable then
            Migrate_To_Version_4 (Item, Metadata, Limits);
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
         if Item.Schema_Version < 7 and then Writable then
            Migrate_To_Version_7 (Item, Metadata, Limits);
            Item.Schema_Version := 7;
         end if;
         if Item.Schema_Version < 8 and then Writable then
            Migrate_To_Version_8 (Item, Metadata, Limits);
            Item.Schema_Version := 8;
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
      Item.Opened := Database.Is_Open (Item.DB);
      if Created and then not Item.Opened then
         Remove_Created_Artifacts;
      end if;
      raise;
end Open;
