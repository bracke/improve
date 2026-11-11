separate (Improve.Storage)
procedure Update_Publication_States
  (Item   : in out Store;
   Plan_Id : String;
   Values : Publication_Vectors.Vector) is
   Tx : Database.Transactions.Transaction;
   Rows : String_Id_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

   function Mapping_Key (Task_Id, Contract : String) return String is
     (Task_Id & Character'Val (0) & Contract);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication reconciliation";
   end if;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Plan_Row); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            Rows.Include
              (Mapping_Key (S (Row.Kind), Field_Or (Payload, "contract", "")), Row.Id);
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
            if Field (Payload, "harness_id") /= To_String (Value.Harness_Task_Id) or else
              Field (Payload, "origin") /= To_String (Value.Origin)
            then
               raise Data_Error with "publication reconciliation identity does not match stored mapping";
            end if;
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
