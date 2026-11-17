--  Persist one immutable remediation-plan revision.
separate (Improve.Storage)
function Save
  (Item   : in out Store;
   Value  : Improve.Model.Plan_Revision;
   Limits : Persistence_Limits := Default_Persistence_Limits) return Save_Result is
      Tx : Database.Transactions.Transaction;
      Stored : Improve.Model.Plan_Revision := Value;
      Existing_Revision : Natural;
      Budget        : History_Budget := New_History_Budget (Limits);
      Read_Bytes    : Natural := 0;
      Written_Bytes : Natural := 0;

      procedure Consume_Read_Row (Kind, State, Payload, Context : String) is
      begin
         Consume_Persistence_Row
           (Limits, Kind, State, Payload, Context, Read_Bytes, "read");
      end Consume_Read_Row;

      procedure Consume_Write_Row (Kind, State, Payload, Context : String) is
      begin
         Consume_Persistence_Row
           (Limits, Kind, State, Payload, Context, Written_Bytes, "write");
      end Consume_Write_Row;

   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for writing";
      end if;
      Validate_Save_Value (Value, Limits);
      Begin_Write_Transaction (Item.DB, Tx);
      Improve.Storage.Allocation.Begin_Transaction (Item);
      Existing_Revision :=
        Find_Revision (Item, Tx, To_String (Value.Fingerprint), Budget);
      if Existing_Revision > 0 then
         Rollback_Transaction (Tx, "finish existing plan lookup");
         declare
            Existing : constant Improve.Model.Plan_Revision :=
              Load_Revision (Item, Positive (Existing_Revision), Limits);
         begin
            Require_Idempotent_Equivalent (Existing, Value);
            return (Plan => Existing, Existing => True);
         end;
      end if;
      Stored.Created_At := Ada.Calendar.Clock;
      declare
         Project_Row  : Positive := 1;
         Baseline_Row : constant Positive := Improve.Storage.Allocation.Next (Item, Tx, Baselines_Table);
         Plan_Row     : Positive := 1;
         Revision_Row : constant Positive := Improve.Storage.Allocation.Next (Item, Tx, Revisions_Table);
         Revision_No  : Positive := 1;
         Previous_Revision : Natural := 0;
         Cursor       : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Plans_Table, Project_Key (Stored.Project));
      begin
         if not Entity_Tables.Has_Element (Cursor) then
            Cursor := Scan_Kind (Item, Tx, Plans_Table, Legacy_Project_Key (Stored.Project));
         end if;
         if Entity_Tables.Has_Element (Cursor) then
            Plan_Row := Entity_Tables.Element (Cursor).Id;
            if Entity_Tables.Element (Cursor).Parent_Id = 0 then
               raise Data_Error with "persisted plan has no project relationship";
            end if;
            Project_Row := Positive (Entity_Tables.Element (Cursor).Parent_Id);
            declare
               Project_Entity : Entity;
               Status : constant Database.Status.Result :=
                 Entity_Tables.Find
                   (Tx, Item.DB, Item.Schemas (Projects_Table),
                    Physical_Key (Projects_Table, Project_Row), Project_Entity);
            begin
               Check (Status, "read persisted project reference");
               declare Payload : constant String := S (Project_Entity.Payload); begin
                  Consume_Read_Row
                    (S (Entity_Tables.Element (Cursor).Kind), S (Entity_Tables.Element (Cursor).State),
                     S (Entity_Tables.Element (Cursor).Payload), "persisted plan");
                  Consume_Read_Row
                    (S (Project_Entity.Kind), S (Project_Entity.State), Payload, "persisted project");
                  if S (Project_Entity.Kind) /= S (Entity_Tables.Element (Cursor).Kind) or else
                    Positive'Value (Field (Payload, "quality_project_id")) /= Stored.Project.Id or else
                    Field (Payload, "name") /= To_String (Stored.Project.Name) or else
                    Field (Payload, "path") /= To_String (Stored.Project.Path) or else
                    Field (Payload, "quality_database") /= To_String (Stored.Project.Database_Id)
                  then
                     raise Data_Error with "stored plan project identity is inconsistent";
                  end if;
               end;
            end;
            declare Revisions : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Plan_Row);
            begin
               while Entity_Tables.Has_Element (Revisions) loop
                  Consume_History (Budget, "plan revision history");
                  if Entity_Tables.Element (Revisions).Parent_Id = Plan_Row then
                     Consume_Read_Row
                       (S (Entity_Tables.Element (Revisions).Kind), S (Entity_Tables.Element (Revisions).State),
                        S (Entity_Tables.Element (Revisions).Payload), "persisted plan revision");
                     Previous_Revision := Natural'Max
                       (Previous_Revision, Entity_Tables.Element (Revisions).Id);
                     Revision_No := Positive'Max
                       (Revision_No,
                        Positive'Value
                          (Field (S (Entity_Tables.Element (Revisions).Payload), "revision")) + 1);
                  end if;
                  Advance_Children (Item, Tx, Revisions_Table, Plan_Row, Revisions);
               end loop;
            end;
         else
            Project_Row := Improve.Storage.Allocation.Next (Item, Tx, Projects_Table);
            Plan_Row := Improve.Storage.Allocation.Next (Item, Tx, Plans_Table);
            declare
               Key : constant String := Project_Key (Stored.Project);
               Payload : constant String :=
                 Pair ("name", To_String (Stored.Project.Name)) & LF &
                 Pair ("path", To_String (Stored.Project.Path)) & LF &
                 Pair ("quality_database", To_String (Stored.Project.Database_Id)) & LF &
                 Pair ("quality_project_id", Number (Stored.Project.Id));
            begin
               Consume_Write_Row (Key, "active", Payload, "project reference");
               Consume_Write_Row (Key, "active", "", "plan");
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Projects_Table),
                     (Project_Row, 0, WW (Key), WW ("active"), WW (Payload), True, Projects_Table)),
                  "store project");
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Plans_Table),
                     (Plan_Row, Project_Row, WW (Key), WW ("active"), WW (""), True, Plans_Table)),
                  "store plan");
            end;
         end if;
         Stored.Plan_Id := To_Unbounded_String (Id_Image ("PLAN-", Plan_Row));
         Stored.Revision := Revision_No;
         declare
            Baseline_Kind : constant String := Number (Stored.Baseline.Run_Id);
            Baseline_Payload : constant String :=
              Pair ("source", To_String (Stored.Baseline.Source_Id)) & LF &
              Pair ("policy", To_String (Stored.Baseline.Policy_Id)) & LF &
              Pair ("toolchain", To_String (Stored.Baseline.Toolchain_Id)) & LF &
              Pair ("assessment", To_String (Stored.Baseline.Evidence_Id)) & LF &
              Pair ("snapshot", To_String (Stored.Baseline.Snapshot_Id));
            Revision_Kind : constant String := To_String (Stored.Fingerprint);
            Revision_State : constant String := To_String (Stored.Review_Status);
            Revision_Data : constant String := Revision_Payload (Stored, Baseline_Row, Revision_No);
         begin
            Consume_Write_Row (Baseline_Kind, "completed", Baseline_Payload, "assessment baseline");
            Consume_Write_Row (Revision_Kind, Revision_State, Revision_Data, "plan revision");
            Consume_History (Budget, "plan revision history");
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Baselines_Table),
                  (Baseline_Row, Project_Row, WW (Baseline_Kind), WW ("completed"),
                   WW (Baseline_Payload), True, Baselines_Table)),
               "store baseline");
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Revisions_Table),
                  (Revision_Row, Plan_Row, WW (Revision_Kind), WW (Revision_State),
                   WW (Revision_Data), True, Revisions_Table)),
               "store plan revision");
         end;
         declare
            Finding_Row : Positive;
         begin
            for Finding of Stored.Findings loop
               Finding_Row := Improve.Storage.Allocation.Next (Item, Tx, Findings_Table);
               Consume_Write_Row
                 (To_String (Finding.Fingerprint), Improve.Model.Image (Finding.Kind),
                  Finding_Payload (Finding), "finding");
               Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Findings_Table),
                      (Finding_Row, Revision_Row, WW (To_String (Finding.Fingerprint)),
                       WW (Improve.Model.Image (Finding.Kind)), WW (Finding_Payload (Finding)), True, Findings_Table)),
                      "store finding");
            end loop;
         end;
         declare
            First_Task_Row : constant Positive :=
              (if Stored.Tasks.Is_Empty then 1
               else Improve.Storage.Allocation.Reserve
                 (Item, Tx, Tasks_Table, Positive (Stored.Tasks.Length)));
            Assigned_Ids : String_Id_Maps.Map;
            Previous_Tasks : String_Value_Maps.Map;
            Assigned_By_Original : String_Value_Maps.Map;
         begin
            if not Stored.Tasks.Is_Empty then
               Index_Previous_Tasks
                 (Item, Tx, Previous_Revision, Limits, Read_Bytes, Previous_Tasks);
            end if;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               declare
                  Original : constant Ada.Strings.Unbounded.Unbounded_String := Stored.Tasks (Index).Id;
                  Prior : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Previous_Task_Id (Stored.Tasks (Index), Stored.Findings, Previous_Tasks);
                  Identity : constant Ada.Strings.Unbounded.Unbounded_String :=
                    (if Length (Prior) > 0 and then not Assigned_Ids.Contains (To_String (Prior)) then Prior
                     else To_Unbounded_String (Id_Image ("IMP-", First_Task_Row + Index - 1)));
               begin
                  if Assigned_By_Original.Contains (To_String (Original)) then
                     raise Data_Error with "plan contains a duplicate task identity";
                  end if;
                  Stored.Tasks (Index).Id := Identity;
                  Assigned_Ids.Insert (To_String (Identity), Index);
                  Assigned_By_Original.Insert (To_String (Original), Identity);
               end;
            end loop;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               declare
                  Task_Row  : constant Positive := First_Task_Row + Index - 1;
                  Persisted : Improve.Model.Task_Specification := Stored.Tasks (Index);
                  Translated : Improve.Model.UString_Vectors.Vector;
               begin
                  for Dependency of Persisted.Dependencies loop
                     declare Identity : constant String := To_String (Dependency); begin
                        if not Assigned_By_Original.Contains (Identity) then
                           raise Data_Error with "task dependency is absent from the persisted plan";
                        end if;
                        Translated.Append (Assigned_By_Original.Element (Identity));
                     end;
                  end loop;
                  Persisted.Dependencies := Translated;
                  Stored.Tasks.Replace_Element (Index, Persisted);
                  Consume_Write_Row
                    (To_String (Persisted.Category), Improve.Model.Image (Persisted.Kind),
                     Task_Payload (Persisted), "task");
                  Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Tasks_Table),
                         (Task_Row, Revision_Row, WW (To_String (Persisted.Category)),
                          WW (Improve.Model.Image (Persisted.Kind)), WW (Task_Payload (Persisted)), True, Tasks_Table)),
                         "store task");
                  declare
                     Identity : constant String := To_String (Persisted.Id);
                     Payload  : constant String := Pair ("task_row", Number (Task_Row));
                  begin
                     Consume_Write_Row (Identity, "active", Payload, "task identity index");
                     Check
                       (Entity_Tables.Insert
                          (Tx, Item.DB, Item.Schemas (Task_Identities_Table),
                           (Improve.Storage.Allocation.Next (Item, Tx, Task_Identities_Table), Revision_Row,
                            WW (Identity), WW ("active"), WW (Payload), True, Task_Identities_Table)),
                        "index task identity");
                  end;
                  declare
                     procedure Add_Detail (Name, Value : String) is
                     begin
                        Consume_Write_Row (Name, "value", Value, "task detail");
                        Check
                          (Entity_Tables.Insert
                             (Tx, Item.DB, Item.Schemas (Task_Details_Table),
                              (Improve.Storage.Allocation.Next (Item, Tx, Task_Details_Table), Task_Row,
                               WW (Name), WW ("value"),
                               WW (Value), True, Task_Details_Table)),
                           "store task detail");
                     end Add_Detail;
                  begin
                     Add_Detail ("goal", To_String (Persisted.Goal));
                     Add_Detail ("problem", To_String (Persisted.Problem));
                     Add_Detail ("evidence", To_String (Persisted.Evidence));
                     Add_Detail ("out_of_scope", To_String (Persisted.Out_Of_Scope));
                     Add_Detail ("requirements", To_String (Persisted.Requirements));
                     Add_Detail ("acceptance", To_String (Persisted.Acceptance));
                     Add_Detail ("verification", To_String (Persisted.Verification));
                  end;
                  for Key of Persisted.Finding_Keys loop
                     Consume_Write_Row (To_String (Key), "linked", "", "task finding link");
                     Check
                       (Entity_Tables.Insert
                          (Tx, Item.DB, Item.Schemas (Task_Findings_Table),
                           (Improve.Storage.Allocation.Next (Item, Tx, Task_Findings_Table), Task_Row,
                            WW (To_String (Key)),
                            WW ("linked"), WW (""), True, Task_Findings_Table)),
                        "store task finding link");
                  end loop;
                  for Dependency of Persisted.Dependencies loop
                     Consume_Write_Row (To_String (Dependency), "required", "", "task dependency link");
                     Check
                       (Entity_Tables.Insert
                          (Tx, Item.DB, Item.Schemas (Task_Dependencies_Table),
                           (Improve.Storage.Allocation.Next (Item, Tx, Task_Dependencies_Table), Task_Row,
                            WW (To_String (Dependency)), WW ("required"), WW (""), True,
                            Task_Dependencies_Table)),
                        "store task dependency");
                  end loop;
               end;
            end loop;
         end;
      end;
      Improve.Storage.Allocation.Flush (Item, Tx);
      Commit_Transaction (Tx, "commit plan revision");
      return (Plan => Stored, Existing => False);
   end Save;
