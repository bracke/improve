separate (Improve.Storage)
procedure Migrate_To_Version_5
  (Item     : in out Store;
   Metadata : in out Entity) is
   Tx : Database.Transactions.Transaction;

   package Id_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);
   Plan_Rows      : Id_Vectors.Vector;
   Revision_Count : Natural := 0;

   procedure Require_Migration_Payload (Text, Context : String) is
   begin
      if Text'Length > Default_Read_Limits.Maximum_Text_Bytes then
         raise Data_Error with Context & " exceeds the configured payload limit";
      end if;
   end Require_Migration_Payload;

   function Unique_Project (Kind : String) return Entity is
      Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Projects_Table, Kind);
      Result : Entity;
   begin
      if not Entity_Tables.Has_Element (Cursor) then
         raise Data_Error with "plan has no persisted project reference";
      end if;
      Result := Entity_Tables.Element (Cursor);
      Advance_Kind (Item, Tx, Projects_Table, Kind, Cursor);
      if Entity_Tables.Has_Element (Cursor) then
         raise Data_Error with "plan has ambiguous persisted project references";
      end if;
      return Result;
   end Unique_Project;
begin
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Plans : Entity_Tables.Cursor := Scan (Item, Tx, Plans_Table); begin
      while Entity_Tables.Has_Element (Plans) loop
         if Plan_Rows.Length >= Ada.Containers.Count_Type (Default_Query_Maximum) then
            raise Data_Error with "schema migration exceeds the configured plan limit";
         end if;
         Plan_Rows.Append (Entity_Tables.Element (Plans).Id);
         Advance (Item, Tx, Plans_Table, Plans);
      end loop;
   end;
   for Plan_Id of Plan_Rows loop
      declare
         Plan_Row    : Entity;
         Plan_Status : constant Database.Status.Result :=
           Entity_Tables.Find
             (Tx, Item.DB, Item.Schemas (Plans_Table),
              Physical_Key (Plans_Table, Plan_Id), Plan_Row);
         Quality_Id  : Natural := 0;
         Seen        : Boolean := False;
      begin
         Check (Plan_Status, "read migration plan");
         declare
            Project_Row : Entity := Unique_Project (S (Plan_Row.Kind));
            Revisions   : Entity_Tables.Cursor :=
              Scan_Children (Item, Tx, Revisions_Table, Plan_Row.Id);
         begin
            Require_Migration_Payload
              (S (Project_Row.Payload), "migration project payload");
            while Entity_Tables.Has_Element (Revisions) loop
               if Revision_Count >= Default_Read_Limits.Maximum_History then
                  raise Data_Error with "schema migration exceeds the configured revision limit";
               end if;
               Revision_Count := Revision_Count + 1;
               declare
                  Revision : constant Entity := Entity_Tables.Element (Revisions);
                  Payload  : constant String := S (Revision.Payload);
                  Baseline : Entity;
                  Baseline_Id : Positive;
                  Revision_Project : Positive;
                  Status : Database.Status.Result;
               begin
                  Require_Migration_Payload
                    (Payload, "migration revision payload");
                  Baseline_Id := Positive'Value (Field (Payload, "baseline_id"));
                  Revision_Project := Positive'Value (Field (Payload, "project_id"));
                  Status := Entity_Tables.Find
                    (Tx, Item.DB, Item.Schemas (Baselines_Table),
                     Physical_Key (Baselines_Table, Baseline_Id), Baseline);
                  Check (Status, "read migration baseline");
                  Require_Migration_Payload
                    (S (Baseline.Payload), "migration baseline payload");
                  if Quality_Id = 0 then
                     Quality_Id := Revision_Project;
                  elsif Quality_Id /= Revision_Project then
                     raise Data_Error with "plan revisions disagree on quality project identity";
                  end if;
                  if Field (S (Project_Row.Payload), "name") /= Field (Payload, "project") or else
                    Field (S (Project_Row.Payload), "path") /= Field (Payload, "project_path") or else
                    Field (S (Project_Row.Payload), "quality_database") /=
                      Field_Or (Payload, "quality_database", "")
                  then
                     raise Data_Error with "plan revision disagrees with its project reference";
                  elsif S (Baseline.Kind) /= Field (Payload, "run_id") or else
                    Field (S (Baseline.Payload), "source") /= Field (Payload, "source") or else
                    Field (S (Baseline.Payload), "policy") /= Field (Payload, "policy") or else
                    Field (S (Baseline.Payload), "toolchain") /= Field (Payload, "toolchain") or else
                    Field (S (Baseline.Payload), "snapshot") /= Field (Payload, "snapshot")
                  then
                     raise Data_Error with "plan revision disagrees with its assessment baseline";
                  end if;
                  Baseline.Parent_Id := Project_Row.Id;
                  Check
                    (Entity_Tables.Update
                       (Tx, Item.DB, Item.Schemas (Baselines_Table), Baseline),
                     "link assessment baseline to project");
                  Seen := True;
               end;
               Advance_Children (Item, Tx, Revisions_Table, Plan_Row.Id, Revisions);
            end loop;
            if not Seen then
               raise Data_Error with "persisted plan has no revision";
            end if;
            Plan_Row.Parent_Id := Project_Row.Id;
            Check
              (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Plans_Table), Plan_Row),
               "link plan to project");
            declare Payload : constant String := S (Project_Row.Payload); begin
               if Field_Or (Payload, "quality_project_id", "") = "" then
                  Project_Row.Payload := WW
                    (Payload & LF & Pair ("quality_project_id", Number (Quality_Id)));
               elsif Positive'Value (Field (Payload, "quality_project_id")) /= Quality_Id then
                  raise Data_Error with "persisted project reference has conflicting quality identity";
               end if;
            end;
            Check
              (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Project_Row),
               "qualify project identity");
         end;
      end;
   end loop;
   Metadata.State := WW ("5");
   Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
   Check
     (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
      "migrate normalized project relationships");
   Database.Transactions.Commit (Tx);
exception
   when Constraint_Error =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise Data_Error with "schema version 5 migration data is malformed";
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Migrate_To_Version_5;
