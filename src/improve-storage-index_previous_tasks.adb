--  Index reusable task identities from the preceding immutable revision.
separate (Improve.Storage)
procedure Index_Previous_Tasks
  (Item              : in out Store;
   Tx                : in out Database.Transactions.Transaction;
   Previous_Revision : Natural;
   Limits            : Persistence_Limits;
   Consumed_Bytes    : in out Natural;
   Previous_Tasks    : in out String_Value_Maps.Map) is
   Tasks        : Entity_Tables.Cursor;
   Task_Count   : Natural := 0;
   Detail_Count : Natural := 0;

begin
   if Previous_Revision = 0 then
      return;
   end if;
   Tasks := Scan_Children (Item, Tx, Tasks_Table, Positive (Previous_Revision));
   while Entity_Tables.Has_Element (Tasks) loop
      if Task_Count >= Limits.Maximum_Tasks then
         raise Data_Error with "previous plan revision exceeds configured task limit";
      end if;
      Task_Count := Task_Count + 1;
      declare
         Row     : constant Entity := Entity_Tables.Element (Tasks);
         Payload : constant String := S (Row.Payload);
      begin
         Consume_Persistence_Row
           (Limits, S (Row.Kind), S (Row.State), Payload, "previous task",
            Consumed_Bytes, "read");
         declare
            Has_Inline_Acceptance : constant Boolean := Has_Field (Payload, "acceptance");
            Acceptance            : Unbounded_String :=
              To_Unbounded_String (Field_Or (Payload, "acceptance", ""));
            Details               : Entity_Tables.Cursor :=
              Scan_Children (Item, Tx, Task_Details_Table, Row.Id);
            Seen_Details          : String_Id_Maps.Map;
         begin
            while Entity_Tables.Has_Element (Details) loop
               if Detail_Count >= Limits.Maximum_Task_Details then
                  raise Data_Error with "previous plan revision exceeds configured task-detail limit";
               end if;
               Detail_Count := Detail_Count + 1;
               declare
                  Detail : constant Entity := Entity_Tables.Element (Details);
                  Name   : constant String := S (Detail.Kind);
               begin
                  Consume_Persistence_Row
                    (Limits, Name, S (Detail.State), S (Detail.Payload), "previous task detail",
                     Consumed_Bytes, "read");
                  if S (Detail.State) /= "value" then
                     raise Data_Error with "previous task detail has an invalid state";
                  elsif Seen_Details.Contains (Name) then
                     raise Data_Error with "duplicate persisted task detail " & Name;
                  end if;
                  Seen_Details.Insert (Name, Detail.Id);
                  if Name = "acceptance" then
                     if Has_Inline_Acceptance then
                        raise Data_Error with
                          "task acceptance has conflicting inline and normalized representations";
                     end if;
                     Acceptance := To_Unbounded_String (S (Detail.Payload));
                  end if;
               end;
               Advance_Children (Item, Tx, Task_Details_Table, Row.Id, Details);
            end loop;
            declare
               Key : constant String :=
                 Task_Identity_Key
                   (S (Row.Kind), Field (Payload, "title"), To_String (Acceptance),
                    Stored_Finding_Set (Payload));
            begin
               if not Previous_Tasks.Contains (Key) then
                  Previous_Tasks.Insert (Key, To_Unbounded_String (Field (Payload, "draft_id")));
               end if;
            end;
         end;
      end;
      Advance_Children (Item, Tx, Tasks_Table, Positive (Previous_Revision), Tasks);
   end loop;
end Index_Previous_Tasks;
