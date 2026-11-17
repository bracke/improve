separate (Improve.Storage)
function Is_Approved
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Persistence_Limits := Default_Persistence_Limits) return Boolean is
   Plan   : Improve.Model.Plan_Revision;
   Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
   Tx     : Database.Transactions.Transaction;
   Result : Boolean := False;
   Budget : History_Budget := New_History_Budget (Limits);
   Content : Unbounded_String;
begin
   Plan := Load_Exact (Item, Plan_Id, Revision, Limits, Budget);
   Content := To_Unbounded_String (Improve.Model.Plan_Content_Fingerprint (Plan));
   Begin_Read_Transaction (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "plan approval history");
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
              Data.Fingerprint = Plan.Fingerprint and then
              Data.Content_Fingerprint = Content
            then
               Result := True;
               exit;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
      end loop;
   end;
   Rollback_Transaction (Tx, "finish approval query");
   return Result;
end Is_Approved;
