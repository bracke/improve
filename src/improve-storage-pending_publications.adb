separate (Improve.Storage)
function Pending_Publications
  (Item    : in out Store;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Persistence_Limits := Default_Persistence_Limits) return Operation_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Operation_Vectors.Vector;
   Budget : History_Budget := New_History_Budget (Limits);
begin
   Begin_Read_Transaction (Item.DB, Tx);
   declare Starts : Entity_Tables.Cursor := Scan_State (Item, Tx, Operations_Table, "started"); begin
      while Entity_Tables.Has_Element (Starts) loop
         Consume_History (Budget, "publication operation history");
         declare
            Row       : constant Entity := Entity_Tables.Element (Starts);
            Completed : Boolean := False;
            Ends      : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Row.Id);
            Payload   : constant String := S (Row.Payload);
            Data      : Improve.Persistence_Records.Publication_Operation_Data;
         begin
            if Row.Parent_Id /= 0 then
               raise Data_Error with "publication operation has an unexpected parent";
            end if;
            Require_Payload_Limit (Payload, Limits, "publication operation payload");
            Data := Improve.Persistence_Records.Decode_Publication_Operation
              (Payload, Limits.Maximum_Tasks, Limits.Maximum_Text_Bytes);
            if Length (Data.Task_Kind) > 0 and then
              Improve.Persistence_Validation.Operation_Key (Data) /= S (Row.Kind)
            then
               raise Data_Error with "publication operation identity is inconsistent";
            end if;
            while Entity_Tables.Has_Element (Ends) loop
               Consume_History (Budget, "publication operation history");
               declare Completion : constant Entity := Entity_Tables.Element (Ends); begin
                  if S (Completion.Kind) /= S (Row.Kind) or else S (Completion.State) /= "completed" then
                     raise Data_Error with "publication completion identity is inconsistent";
                  elsif S (Completion.Payload) /= Payload then
                     raise Data_Error with "publication completion does not match its operation";
                  elsif Completed then
                     raise Data_Error with "duplicate publication completion";
                  end if;
                  Completed := True;
               end;
               Advance_Children (Item, Tx, Operations_Table, Row.Id, Ends);
            end loop;
            if not Completed then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "pending publication query exceeds configured item limit";
               end if;
               Result.Append
                 (Operation_Record'
                    (Id          => Row.Id,
                     Key         => To_Unbounded_String (S (Row.Kind)),
                     Plan_Id     => Data.Plan_Id,
                     Revision    => Data.Revision,
                     Fingerprint => Data.Fingerprint,
                     Content_Fingerprint => Data.Content_Fingerprint,
                     Task_Kind   => Data.Task_Kind,
                     Task_Ids    => Data.Task_Ids));
            end if;
         end;
         Advance_State (Item, Tx, Operations_Table, "started", Starts);
      end loop;
   end;
   Rollback_Transaction (Tx, "finish pending publication query");
   return Result;
end Pending_Publications;
