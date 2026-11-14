separate (Improve.Storage)
procedure Record_Publications
  (Item    : in out Store;
   Plan_Id : String;
   Values  : Publication_Vectors.Vector;
   Limits  : Read_Limits := Default_Read_Limits) is
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Stored : String_Value_Maps.Map;
   Contracts : String_Value_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);
   History_Count : Natural := 0;

   function Mapping_Key (Task_Id, Contract : String) return String is
     (Task_Id & Character'Val (0) & Contract);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication recording";
   elsif Values.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
      raise Data_Error with "publication recording exceeds configured task limit";
   end if;
   for Value of Values loop
      Cache_Contracts (Item, Plan_Id, Value.Plan_Revision, Limits, Contracts);
      declare
         Key : constant String :=
           Contract_Key (Plan_Id, Value.Plan_Revision, To_String (Value.Improve_Task_Id));
      begin
         if not Contracts.Contains (Key) then
            raise Data_Error with "publication references an unknown persisted task";
         elsif Value.Contract /= Contracts.Element (Key) then
            raise Data_Error with "publication does not match the persisted task contract";
         elsif Length (Value.Harness_Task_Id) = 0 or else Length (Value.Origin) = 0 then
            raise Data_Error with "publication mapping is incomplete";
         end if;
      end;
   end loop;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Plan_Row); begin
      while Entity_Tables.Has_Element (Cursor) loop
         if History_Count >= Limits.Maximum_History then
            raise Data_Error with "publication history exceeds configured item limit";
         end if;
         History_Count := History_Count + 1;
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
            Data    : Improve.Persistence_Records.Publication_Data;
         begin
            Require_Payload_Limit (Payload, Limits, "publication mapping payload");
            Data := Improve.Persistence_Records.Decode_Publication (Payload);
            Improve.Persistence_Validation.Validate (Data, Plan_Id);
            declare Key : constant String :=
              Mapping_Key (S (Row.Kind), To_String (Data.Contract));
            begin
               if Stored.Contains (Key) then
                  raise Data_Error with "duplicate persisted publication mapping";
               end if;
               Stored.Insert
              (Key,
               To_Unbounded_String
                 (To_String (Data.Harness_Id) & Character'Val (0) & To_String (Data.Origin)));
            end;
         end;
         Advance_Children (Item, Tx, Publications_Table, Plan_Row, Cursor);
      end loop;
   end;
   for Value of Values loop
      declare
         Key      : constant String := Mapping_Key
           (To_String (Value.Improve_Task_Id), To_String (Value.Contract));
         Expected : constant String :=
           To_String (Value.Harness_Task_Id) & Character'Val (0) & To_String (Value.Origin);
         Existing : constant Boolean := Stored.Contains (Key);
         Payload  : constant String := Improve.Persistence_Records.Encode_Publication
           ((Plan_Id       => To_Unbounded_String (Plan_Id),
             Harness_Id    => Value.Harness_Task_Id,
             Origin        => Value.Origin,
             Contract      => Value.Contract,
             Plan_Revision => Value.Plan_Revision));
      begin
         if Existing and then To_String (Stored.Element (Key)) /= Expected then
            raise Data_Error with "published task identity is already mapped to unrelated work";
         end if;
         if not Existing then
            if History_Count >= Limits.Maximum_History then
               raise Data_Error with "publication history exceeds configured item limit";
            end if;
            Require_Payload_Limit (Payload, Limits, "publication mapping payload");
            Row_Id := Next_Id (Item, Tx, Publications_Table);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Publications_Table),
                  (Row_Id, Plan_Row, WW (To_String (Value.Improve_Task_Id)), WW (To_String (Value.State)),
                   WW (Payload), True, Publications_Table)),
               "record publication mapping");
            Stored.Insert (Key, To_Unbounded_String (Expected));
            History_Count := History_Count + 1;
         end if;
      end;
   end loop;
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Record_Publications;
