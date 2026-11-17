separate (Improve.Storage)
procedure Complete_Publication
  (Item         : in out Store;
   Operation_Id : Positive;
   Limits       : Persistence_Limits := Default_Persistence_Limits) is
   Tx      : Database.Transactions.Transaction;
   Started : Entity;
   Found   : Boolean := False;
   Completion_Found : Boolean := False;
   Row_Id  : Positive;
   Budget : History_Budget := New_History_Budget (Limits);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication completion";
   end if;
   Begin_Write_Transaction (Item.DB, Tx);
   Improve.Storage.Allocation.Begin_Transaction (Item);
   declare
      Status : constant Database.Status.Result :=
        Entity_Tables.Find
          (Tx, Item.DB, Item.Schemas (Operations_Table),
           Physical_Key (Operations_Table, Operation_Id), Started);
   begin
      if Database.Status.Is_Ok (Status) and then S (Started.State) = "started" then
         Consume_History (Budget, "publication operation history");
         Require_Payload_Limit
           (S (Started.Payload), Limits, "publication operation payload");
         declare
            Data : constant Improve.Persistence_Records.Publication_Operation_Data :=
              Improve.Persistence_Records.Decode_Publication_Operation
                (S (Started.Payload), Limits.Maximum_Tasks, Limits.Maximum_Text_Bytes);
         begin
            if Started.Parent_Id /= 0 or else
              (Length (Data.Task_Kind) > 0 and then
               Improve.Persistence_Validation.Operation_Key (Data) /= S (Started.Kind))
            then
               raise Data_Error with "publication operation identity is inconsistent";
            end if;
         end;
         Found := True;
      elsif Status.Code /= Database.Status.Not_Found then
         Check (Status, "read publication operation");
      end if;
   end;
   if not Found then raise Data_Error with "unknown publication operation"; end if;
   declare Ends : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Operation_Id); begin
      while Entity_Tables.Has_Element (Ends) loop
         Consume_History (Budget, "publication completion history");
         declare Completion : constant Entity := Entity_Tables.Element (Ends); begin
            if S (Completion.Kind) /= S (Started.Kind) or else S (Completion.State) /= "completed" then
               raise Data_Error with "publication completion identity is inconsistent";
            elsif S (Completion.Payload) /= S (Started.Payload) then
               raise Data_Error with "publication completion does not match its operation";
            elsif Completion_Found then
               raise Data_Error with "duplicate publication completion";
            end if;
            Completion_Found := True;
         end;
         Advance_Children (Item, Tx, Operations_Table, Operation_Id, Ends);
      end loop;
   end;
   if Completion_Found then
      Rollback_Transaction (Tx, "finish existing publication completion lookup");
      return;
   end if;
   Consume_History (Budget, "publication completion history");
   Row_Id := Improve.Storage.Allocation.Next (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, Operation_Id, Started.Kind, WW ("completed"), Started.Payload, True, Operations_Table)),
      "journal publication completion");
   Improve.Storage.Allocation.Flush (Item, Tx);
   Commit_Transaction (Tx, "commit publication completion");
end Complete_Publication;
