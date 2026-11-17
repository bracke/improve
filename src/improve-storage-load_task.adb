separate (Improve.Storage)
function Load_Task
  (Item     : in out Store;
   Task_Id  : String;
   Revision : Natural := 0;
   Limits   : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision is
   Tx               : Database.Transactions.Transaction;
   Revision_Id      : Natural := 0;
   Budget           : History_Budget := New_History_Budget (Limits);
   Seen_Revisions   : String_Id_Maps.Map;

   procedure Select_Revision (Candidate : Positive) is
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
      Require_Payload_Limit (S (Row.Payload), Limits, "task revision payload");
      if Positive'Value (Field (S (Row.Payload), "revision")) = Revision then
         Revision_Id := Candidate;
      end if;
   end Select_Revision;

   procedure Consider_Identity (Identity : Entity) is
      Payload   : constant String := S (Identity.Payload);
      Candidate : Positive;
      Task_Row  : Positive;
      Task_Entity : Entity;
      Status    : Database.Status.Result;
   begin
      Require_Payload_Limit (Payload, Limits, "task identity payload");
      if not Identity.Active or else S (Identity.Kind) /= Task_Id or else
        S (Identity.State) /= "active" or else Identity.Parent_Id = 0
      then
         raise Data_Error with "stored task identity index is inconsistent";
      end if;
      Candidate := Positive (Identity.Parent_Id);
      Task_Row := Positive'Value (Field (Payload, "task_row"));
      if Payload /= Pair ("task_row", Number (Task_Row)) then
         raise Data_Error with "stored task identity payload is noncanonical";
      elsif Seen_Revisions.Contains (Number (Candidate)) then
         raise Data_Error with "duplicate stored task identity revision";
      end if;
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Tasks_Table), Physical_Key (Tasks_Table, Task_Row), Task_Entity);
      Check (Status, "read indexed task identity");
      Require_Payload_Limit (S (Task_Entity.Payload), Limits, "indexed task payload");
      if not Task_Entity.Active or else Task_Entity.Parent_Id /= Candidate or else
        Field (S (Task_Entity.Payload), "draft_id") /= Task_Id
      then
         raise Data_Error with "stored task identity does not match its task record";
      end if;
      Seen_Revisions.Insert (Number (Candidate), Task_Row);
      Select_Revision (Candidate);
   end Consider_Identity;
begin
   Begin_Read_Transaction (Item.DB, Tx);
   if Item.Schema_Version >= 4 then
      declare Identities : Entity_Tables.Cursor :=
        Scan_Kind (Item, Tx, Task_Identities_Table, Task_Id);
      begin
         while Entity_Tables.Has_Element (Identities) loop
            Consume_History (Budget, "task identity history");
            Consider_Identity (Entity_Tables.Element (Identities));
            Advance_Kind (Item, Tx, Task_Identities_Table, Task_Id, Identities);
         end loop;
      end;
   else
      declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
         while Entity_Tables.Has_Element (Tasks) loop
            Consume_History (Budget, "task history");
            declare
               Task_Row : constant Entity := Entity_Tables.Element (Tasks);
               Payload  : constant String := S (Task_Row.Payload);
            begin
               Require_Payload_Limit (Payload, Limits, "task payload");
               if Field_Or (Payload, "draft_id", "") = Task_Id then
                  Select_Revision (Positive (Task_Row.Parent_Id));
               end if;
            end;
            Advance (Item, Tx, Tasks_Table, Tasks);
         end loop;
      end;
   end if;
   Rollback_Transaction (Tx, "finish historical task query");
   if Revision_Id = 0 then
      raise Argument_Error with
        "unknown Improve task " & Task_Id &
        (if Revision = 0 then "" else " in revision " & Number (Revision));
   end if;
   return Load_Revision (Item, Positive (Revision_Id), Limits);
exception
   when Constraint_Error =>
      raise Data_Error with "stored task revision is malformed";
end Load_Task;
