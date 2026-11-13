separate (Improve.Storage)
procedure Update_Publication_States
  (Item   : in out Store;
   Plan_Id : String;
   Values : Publication_Vectors.Vector;
   Limits : Read_Limits := Default_Read_Limits) is
   Tx : Database.Transactions.Transaction;
   Rows : String_Id_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);
   History_Count : Natural := 0;

   function Mapping_Key (Task_Id, Contract : String) return String is
     (Task_Id & Character'Val (0) & Contract);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication reconciliation";
   elsif Values.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
      raise Data_Error with "publication reconciliation exceeds configured task limit";
   end if;
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
            Rows.Include
              (Mapping_Key (S (Row.Kind), To_String (Data.Contract)), Row.Id);
         end;
         Advance_Children (Item, Tx, Publications_Table, Plan_Row, Cursor);
      end loop;
   end;
   for Value of Values loop
      declare
         Key : constant String := Mapping_Key
           (To_String (Value.Improve_Task_Id), To_String (Value.Contract));
         Row : Entity;
         Status : Database.Status.Result;
      begin
         if not Rows.Contains (Key) then
            raise Data_Error with "publication reconciliation references an unknown Improve task";
         end if;
         Status := Entity_Tables.Find
           (Tx, Item.DB, Item.Schemas (Publications_Table),
            Physical_Key (Publications_Table, Rows.Element (Key)), Row);
         Check (Status, "read publication mapping for reconciliation");
         declare Payload : constant String := S (Row.Payload); begin
            Require_Payload_Limit (Payload, Limits, "publication mapping payload");
            declare Data : constant Improve.Persistence_Records.Publication_Data :=
              Improve.Persistence_Records.Decode_Publication (Payload);
            begin
               if Data.Harness_Id /= Value.Harness_Task_Id or else Data.Origin /= Value.Origin
               then
                  raise Data_Error with "publication reconciliation identity does not match stored mapping";
               end if;
            end;
         end;
         Row.State := WW (To_String (Value.State));
         Check
           (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Publications_Table), Row),
            "update reconciled publication state");
      end;
   end loop;
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Update_Publication_States;
