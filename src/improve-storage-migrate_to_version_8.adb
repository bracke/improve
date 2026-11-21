--  Preserve raw harness extension states alongside their normalized core meaning.
separate (Improve.Storage)
procedure Migrate_To_Version_8
  (Item     : in out Store;
   Metadata : in out Entity;
   Limits   : Persistence_Limits) is
   Tx : Database.Transactions.Transaction;
   package Id_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);
   Rows    : Id_Vectors.Vector;
   Scanned : Natural := 0;
begin
   Begin_Write_Transaction (Item.DB, Tx);
   declare
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table);
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         if Scanned >= Limits.Maximum_Migration_Rows then
            raise Data_Error with "harness-state migration exceeds configured row limit";
         end if;
         Scanned := Scanned + 1;
         Rows.Append (Entity_Tables.Element (Cursor).Id);
         Advance (Item, Tx, Publications_Table, Cursor);
      end loop;
   end;
   for Id of Rows loop
      declare
         Row     : Entity;
         Data    : Improve.Persistence_Records.Publication_Data;
      begin
         Check
           (Entity_Tables.Find
              (Tx, Item.DB, Item.Schemas (Publications_Table),
               Physical_Key (Publications_Table, Id), Row),
            "read publication mapping for harness-state migration");
         declare
            Payload : constant String := S (Row.Payload);
         begin
            Require_Payload_Limit (Payload, Limits, "publication mapping payload migration");
            Data := Improve.Persistence_Records.Decode_Publication (Payload);
         end;
         if Length (Data.Core_State) = 0 then
            if Improve.Harness_States.Is_Known (Improve.Harness_States.Parse_Core (S (Row.State))) then
               Data.Core_State := To_Unbounded_String (S (Row.State));
               Row.Payload := WW (Improve.Persistence_Records.Encode_Publication (Data));
               Require_Payload_Limit (S (Row.Payload), Limits, "publication mapping payload migration");
               Check
                 (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Publications_Table), Row),
                  "add normalized publication state");
            end if;
         end if;
      end;
   end loop;
   Metadata.State := WW ("8");
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "record schema version 8");
   Commit_Transaction (Tx, "commit schema version 8 migration");
end Migrate_To_Version_8;
