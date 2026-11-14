separate (Improve.Storage)
function Pending_Publications
  (Item    : in out Store;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Operation_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Operation_Vectors.Vector;
   History_Count : Natural := 0;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   declare Starts : Entity_Tables.Cursor := Scan_State (Item, Tx, Operations_Table, "started"); begin
      while Entity_Tables.Has_Element (Starts) loop
         if History_Count >= Limits.Maximum_History then
            raise Data_Error with "publication operation history exceeds configured item limit";
         end if;
         History_Count := History_Count + 1;
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
               if History_Count >= Limits.Maximum_History then
                  raise Data_Error with "publication operation history exceeds configured item limit";
               end if;
               History_Count := History_Count + 1;
               declare Completion : constant Entity := Entity_Tables.Element (Ends); begin
                  if S (Completion.State) = "completed" and then
                    S (Completion.Kind) = S (Row.Kind)
                  then
                     if S (Completion.Payload) /= Payload then
                        raise Data_Error with "publication completion does not match its operation";
                     end if;
                     Completed := True;
                     exit;
                  end if;
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
                     Task_Kind   => Data.Task_Kind,
                     Task_Ids    => Data.Task_Ids));
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
