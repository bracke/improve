separate (Improve.Storage)
function Pending_Publications
  (Item    : in out Store;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Operation_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Operation_Vectors.Vector;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   declare Starts : Entity_Tables.Cursor := Scan_State (Item, Tx, Operations_Table, "started"); begin
      while Entity_Tables.Has_Element (Starts) loop
         declare
            Row       : constant Entity := Entity_Tables.Element (Starts);
            Completed : Boolean := False;
            Ends      : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Row.Id);
         begin
            while Entity_Tables.Has_Element (Ends) loop
               if S (Entity_Tables.Element (Ends).State) = "completed" then
                  Completed := True;
                  exit;
               end if;
               Advance_Children (Item, Tx, Operations_Table, Row.Id, Ends);
            end loop;
            if not Completed then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "pending publication query exceeds configured item limit";
               end if;
               declare Payload : constant String := S (Row.Payload); begin
                  Require_Payload_Limit (Payload, Limits, "publication operation payload");
                  Result.Append
                    (Operation_Record'
                       (Id       => Row.Id,
                        Key      => To_Unbounded_String (S (Row.Kind)),
                        Plan_Id  => To_Unbounded_String (Field (Payload, "plan_id")),
                        Revision => Positive'Value (Field_Or (Payload, "revision", "1")),
                        Fingerprint => To_Unbounded_String (Field_Or (Payload, "fingerprint", "")),
                        Task_Ids =>
                          Unpack
                            (Field (Payload, "task_ids"), Limits.Maximum_Tasks,
                             Limits.Maximum_Text_Bytes)));
               end;
            end if;
         end;
         Advance_State (Item, Tx, Operations_Table, "started", Starts);
      end loop;
   end;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Pending_Publications;
