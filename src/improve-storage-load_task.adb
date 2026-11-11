separate (Improve.Storage)
function Load_Task
  (Item     : in out Store;
   Task_Id  : String;
   Revision : Natural := 0;
   Limits   : Read_Limits := Default_Read_Limits) return Improve.Model.Plan_Revision is
   Tx               : Database.Transactions.Transaction;
   Revision_Id      : Natural := 0;

   procedure Consider (Candidate : Positive) is
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      if Revision = 0 then
         Revision_Id := Natural'Max (Revision_Id, Candidate);
         return;
      end if;
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Revisions_Table),
         Physical_Key (Revisions_Table, Candidate), Row);
      Check (Status, "read task plan revision");
      if Positive'Value (Field (S (Row.Payload), "revision")) = Revision then
         Revision_Id := Candidate;
      end if;
   end Consider;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   if Item.Schema_Version >= 4 then
      declare Identities : Entity_Tables.Cursor :=
        Scan_Kind (Item, Tx, Task_Identities_Table, Task_Id);
      begin
         while Entity_Tables.Has_Element (Identities) loop
            Consider (Positive (Entity_Tables.Element (Identities).Parent_Id));
            Advance_Kind (Item, Tx, Task_Identities_Table, Task_Id, Identities);
         end loop;
      end;
   else
      declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
         while Entity_Tables.Has_Element (Tasks) loop
            declare
               Task_Row : constant Entity := Entity_Tables.Element (Tasks);
               Payload  : constant String := S (Task_Row.Payload);
            begin
               if Field_Or (Payload, "draft_id", "") = Task_Id then
                  Consider (Positive (Task_Row.Parent_Id));
               end if;
            end;
            Advance (Item, Tx, Tasks_Table, Tasks);
         end loop;
      end;
   end if;
   Database.Transactions.Rollback (Tx);
   if Revision_Id = 0 then
      raise Argument_Error with
        "unknown Improve task " & Task_Id &
        (if Revision = 0 then "" else " in revision " & Number (Revision));
   end if;
   return Load_Revision (Item, Positive (Revision_Id), Limits);
exception
   when Constraint_Error =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise Data_Error with "stored task revision is malformed";
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Load_Task;
