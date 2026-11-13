separate (Improve.Storage)
procedure Approve
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Read_Limits := Default_Read_Limits) is
   Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
   Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Count  : Natural := 0;
   Payload : constant String := Improve.Persistence_Records.Encode_Approval
     ((Plan_Id     => To_Unbounded_String (Plan_Id),
       Revision    => Revision,
       Fingerprint => Plan.Fingerprint));
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for plan approval";
   end if;
   Require_Payload_Limit (Payload, Limits, "plan approval payload");
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
      while Entity_Tables.Has_Element (Cursor) loop
         if Count >= Limits.Maximum_History then
            raise Data_Error with "plan approval history exceeds configured item limit";
         end if;
         Count := Count + 1;
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Stored  : constant String := S (Row.Payload);
            Data    : Improve.Persistence_Records.Approval_Data;
         begin
            Require_Payload_Limit (Stored, Limits, "plan approval payload");
            Data := Improve.Persistence_Records.Decode_Approval (Stored);
            if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
              Data.Fingerprint = Plan.Fingerprint
            then
               Database.Transactions.Rollback (Tx);
               return;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
      end loop;
   end;
   if Count >= Limits.Maximum_History then
      raise Data_Error with "plan approval history exceeds configured item limit";
   end if;
   Row_Id := Next_Id (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, 0, WW (Key), WW ("approved"),
          WW (Payload), True, Operations_Table)),
      "record plan approval");
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Approve;
