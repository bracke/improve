separate (Improve.Storage)
procedure Complete_Publication (Item : in out Store; Operation_Id : Positive) is
   Tx      : Database.Transactions.Transaction;
   Started : Entity;
   Found   : Boolean := False;
   Row_Id  : Positive;
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
         Found := True;
      elsif Status.Code /= Database.Status.Not_Found then
         Check (Status, "read publication operation");
      end if;
   end;
   if not Found then raise Data_Error with "unknown publication operation"; end if;
   declare Ends : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Operation_Id); begin
      while Entity_Tables.Has_Element (Ends) loop
         if S (Entity_Tables.Element (Ends).State) = "completed" then
            Database.Transactions.Rollback (Tx);
            return;
         end if;
         Advance_Children (Item, Tx, Operations_Table, Operation_Id, Ends);
      end loop;
   end;
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
