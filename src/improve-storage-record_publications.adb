separate (Improve.Storage)
procedure Record_Publications
  (Item    : in out Store;
   Plan_Id : String;
   Values  : Publication_Vectors.Vector) is
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Stored : String_Value_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

   function Mapping_Key (Task_Id, Contract : String) return String is
     (Task_Id & Character'Val (0) & Contract);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication recording";
   end if;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Plan_Row); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            Stored.Include
              (Mapping_Key (S (Row.Kind), Field_Or (Payload, "contract", "")),
               To_Unbounded_String
                 (Field (Payload, "harness_id") & Character'Val (0) & Field (Payload, "origin")));
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
      begin
         if Existing and then To_String (Stored.Element (Key)) /= Expected then
            raise Data_Error with "published task identity is already mapped to unrelated work";
         end if;
         if not Existing then
            Row_Id := Next_Id (Item, Tx, Publications_Table);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Publications_Table),
                  (Row_Id, Plan_Row, WW (To_String (Value.Improve_Task_Id)), WW (To_String (Value.State)),
                   WW (Pair ("plan_id", Plan_Id) & LF &
                       Pair ("harness_id", To_String (Value.Harness_Task_Id)) & LF &
                       Pair ("origin", To_String (Value.Origin)) & LF &
                       Pair ("contract", To_String (Value.Contract)) & LF &
                       Pair ("plan_revision", Number (Value.Plan_Revision))), True, Publications_Table)),
               "record publication mapping");
            Stored.Insert (Key, To_Unbounded_String (Expected));
         end if;
      end;
   end loop;
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Record_Publications;
