separate (Improve.Storage)
function Is_Approved
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Read_Limits := Default_Read_Limits) return Boolean is
   Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
   Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
   Tx     : Database.Transactions.Transaction;
   Result : Boolean := False;
   Count  : Natural := 0;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
      while Entity_Tables.Has_Element (Cursor) loop
         if Count >= Limits.Maximum_History then
            raise Data_Error with "plan approval history exceeds configured item limit";
         end if;
         Count := Count + 1;
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
            Data    : Improve.Persistence_Records.Approval_Data;
         begin
            Require_Payload_Limit (Payload, Limits, "plan approval payload");
            Data := Improve.Persistence_Records.Decode_Approval (Payload);
            Improve.Persistence_Validation.Validate
              (Data, Plan_Id, Revision, To_String (Plan.Fingerprint));
            if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
              Data.Fingerprint = Plan.Fingerprint
            then
               Result := True;
               exit;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
      end loop;
   end;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Is_Approved;
