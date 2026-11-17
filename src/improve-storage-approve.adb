separate (Improve.Storage)
procedure Approve
  (Item     : in out Store;
   Plan_Id  : String;
   Revision : Positive;
   Limits   : Persistence_Limits := Default_Persistence_Limits) is
   Plan   : Improve.Model.Plan_Revision;
   Key    : Unbounded_String;
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Budget : History_Budget := New_History_Budget (Limits);
   Payload : Unbounded_String;
   Content : Unbounded_String;
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for plan approval";
   end if;
   Plan := Load_Exact (Item, Plan_Id, Revision, Limits, Budget);
   Content := To_Unbounded_String (Improve.Model.Plan_Content_Fingerprint (Plan));
   Key := To_Unbounded_String ("approve:" & Plan_Id & ":" & Number (Revision));
   Payload := To_Unbounded_String
     (Improve.Persistence_Records.Encode_Approval
        ((Plan_Id     => To_Unbounded_String (Plan_Id),
          Revision    => Revision,
          Fingerprint => Plan.Fingerprint,
          Content_Fingerprint => Content)));
   Require_Payload_Limit (To_String (Payload), Limits, "plan approval payload");
   Begin_Write_Transaction (Item.DB, Tx);
   Improve.Storage.Allocation.Begin_Transaction (Item);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, To_String (Key)); begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "plan approval history");
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Stored  : constant String := S (Row.Payload);
            Data    : Improve.Persistence_Records.Approval_Data;
         begin
            Require_Payload_Limit (Stored, Limits, "plan approval payload");
            Data := Improve.Persistence_Records.Decode_Approval (Stored);
            Improve.Persistence_Validation.Validate
              (Data, Plan_Id, Revision, To_String (Plan.Fingerprint));
            if S (Row.Kind) = To_String (Key) and then S (Row.State) = "approved" and then
              Data.Fingerprint = Plan.Fingerprint and then Data.Content_Fingerprint = Content
            then
               Rollback_Transaction (Tx, "finish existing approval lookup");
               return;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, To_String (Key), Cursor);
      end loop;
   end;
   Consume_History (Budget, "plan approval history");
   Row_Id := Improve.Storage.Allocation.Next (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, 0, WW (To_String (Key)), WW ("approved"),
          WW (To_String (Payload)), True, Operations_Table)),
      "record plan approval");
   Improve.Storage.Allocation.Flush (Item, Tx);
   Commit_Transaction (Tx, "commit plan approval");
end Approve;
