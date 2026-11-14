separate (Improve.Storage)
procedure Complete_Publication
  (Item         : in out Store;
   Operation_Id : Positive;
   Limits       : Read_Limits := Default_Read_Limits) is
   Tx      : Database.Transactions.Transaction;
   Started : Entity;
   Found   : Boolean := False;
   Row_Id  : Positive;
   History_Count : Natural := 0;
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication completion";
   end if;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare
      Status : constant Database.Status.Result :=
        Entity_Tables.Find
          (Tx, Item.DB, Item.Schemas (Operations_Table),
           Physical_Key (Operations_Table, Operation_Id), Started);
   begin
      if Database.Status.Is_Ok (Status) and then S (Started.State) = "started" then
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
   declare Ends : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, S (Started.Kind)); begin
      while Entity_Tables.Has_Element (Ends) loop
         declare Completion : constant Entity := Entity_Tables.Element (Ends); begin
            if Completion.Parent_Id = Operation_Id and then
              S (Completion.State) = "completed"
            then
               if History_Count >= Limits.Maximum_History then
                  raise Data_Error with "publication completion history exceeds configured item limit";
               end if;
               History_Count := History_Count + 1;
               if S (Completion.Payload) /= S (Started.Payload) then
                  raise Data_Error with "publication completion does not match its operation";
               end if;
               Database.Transactions.Rollback (Tx);
               return;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, S (Started.Kind), Ends);
      end loop;
   end;
   if History_Count >= Limits.Maximum_History then
      raise Data_Error with "publication completion history exceeds configured item limit";
   end if;
   Row_Id := Next_Id (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, Operation_Id, Started.Kind, WW ("completed"), Started.Payload, True, Operations_Table)),
      "journal publication completion");
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Complete_Publication;
