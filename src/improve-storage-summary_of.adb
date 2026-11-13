separate (Improve.Storage)
function Summary_Of
  (Item        : in out Store;
   Tx          : in out Database.Transactions.Transaction;
   Revision_Id : Positive) return Plan_Summary is
   Revision : Entity;
   Status   : Database.Status.Result;
   Tasks    : Natural := 0;
begin
   Status := Entity_Tables.Find
     (Tx, Item.DB, Item.Schemas (Revisions_Table),
      Physical_Key (Revisions_Table, Revision_Id), Revision);
   Check (Status, "read plan revision summary");
   declare
      Payload    : constant String := S (Revision.Payload);
      Provenance : constant Stored_Provenance := Provenance_Of (Item, Tx, Revision, Payload);
   begin
      Require_Payload_Limit (Payload, Default_Read_Limits, "plan revision summary payload");
      if Item.Schema_Version < 5 and then Has_Field (Payload, "task_count") then
         Tasks := Natural'Value (Field (Payload, "task_count"));
      else
         declare Cursor : Entity_Tables.Cursor :=
           Scan_Children (Item, Tx, Tasks_Table, Revision_Id);
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               if Tasks >= Default_Read_Limits.Maximum_Tasks then
                  raise Data_Error with "plan summary exceeds configured task read limit";
               end if;
               Tasks := Tasks + 1;
               Advance_Children (Item, Tx, Tasks_Table, Revision_Id, Cursor);
            end loop;
         end;
         if Has_Field (Payload, "task_count") and then
           Natural'Value (Field (Payload, "task_count")) /= Tasks
         then
            raise Data_Error with "stored plan task count is inconsistent";
         end if;
      end if;
      return
        (Plan_Id     => To_Unbounded_String (Id_Image ("PLAN-", Positive (Revision.Parent_Id))),
         Revision    => Positive'Value (Field (Payload, "revision")),
         Project_Id  => Provenance.Project.Id,
         Project     => Provenance.Project.Name,
         Run_Id      => Provenance.Baseline.Run_Id,
         Task_Count  => Tasks,
         Fingerprint => To_Unbounded_String (S (Revision.Kind)));
   end;
exception
   when Constraint_Error =>
      raise Data_Error with "stored plan summary is malformed";
end Summary_Of;
