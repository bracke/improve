--  Persist one immutable remediation-plan revision.
separate (Improve.Storage)
function Save
  (Item   : in out Store;
   Value  : Improve.Model.Plan_Revision;
   Limits : Read_Limits := Default_Read_Limits) return Save_Result is
      Tx : Database.Transactions.Transaction;
      Stored : Improve.Model.Plan_Revision := Value;
      Existing_Revision : Natural;
      History_Count : Natural := 0;

      procedure Require_Text (Text, Context : String) is
      begin
         if Text'Length > Limits.Maximum_Text_Bytes then
            raise Data_Error with Context & " exceeds configured persisted-text limit";
         end if;
      end Require_Text;

      procedure Validate_Write is
         Detail_Count : Natural := 0;
         Link_Count   : Natural := 0;

         procedure Add_Count (Count, Maximum : Natural; Total : in out Natural; Context : String) is
         begin
            if Count > Maximum - Total then
               raise Data_Error with Context;
            end if;
            Total := Total + Count;
         end Add_Count;
      begin
         if Value.Findings.Length > Ada.Containers.Count_Type (Limits.Maximum_Findings) then
            raise Data_Error with "plan exceeds configured finding write limit";
         elsif Value.Tasks.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
            raise Data_Error with "plan exceeds configured task write limit";
         end if;
         Require_Text (Revision_Payload (Value, 1, 1), "plan revision payload");
         for Finding of Value.Findings loop
            Require_Text (Finding_Payload (Finding), "finding payload");
         end loop;
         for Spec of Value.Tasks loop
            Add_Count (7, Limits.Maximum_Task_Details, Detail_Count,
                       "plan exceeds configured task-detail write limit");
            Add_Count
              (Natural (Spec.Relevant_Files.Length) + Natural (Spec.Finding_Keys.Length) +
               Natural (Spec.Dependencies.Length),
               Limits.Maximum_Task_Links, Link_Count,
               "plan exceeds configured task-link write limit");
            Require_Text (Task_Payload (Spec), "task payload");
            Require_Text (Pack (Spec.Finding_Keys), "task finding links");
            Require_Text (Pack (Spec.Dependencies), "task dependency links");
            Require_Text (To_String (Spec.Goal), "task goal");
            Require_Text (To_String (Spec.Problem), "task problem");
            Require_Text (To_String (Spec.Evidence), "task evidence");
            Require_Text (To_String (Spec.Out_Of_Scope), "task exclusions");
            Require_Text (To_String (Spec.Requirements), "task requirements");
            Require_Text (To_String (Spec.Acceptance), "task acceptance");
            Require_Text (To_String (Spec.Verification), "task verification");
         end loop;
      end Validate_Write;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for writing";
      end if;
      Improve.Model.Validate (Value);
      Validate_Write;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Existing_Revision := Find_Revision (Item, Tx, To_String (Value.Fingerprint));
      if Existing_Revision > 0 then
         Database.Transactions.Rollback (Tx);
         return
           (Plan => Load (Item, "@revision:" & Number (Existing_Revision), Limits),
            Existing => True);
      end if;
      Stored.Created_At := Ada.Calendar.Clock;
      declare
         Project_Row  : Positive := 1;
         Baseline_Row : constant Positive := Next_Id (Item, Tx, Baselines_Table);
         Plan_Row     : Positive := 1;
         Revision_Row : constant Positive := Next_Id (Item, Tx, Revisions_Table);
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
                  if History_Count >= Limits.Maximum_History then
                     raise Data_Error with "plan revision history exceeds configured item limit";
                  end if;
                  History_Count := History_Count + 1;
                  if Entity_Tables.Element (Revisions).Parent_Id = Plan_Row then
                     Require_Text
                       (S (Entity_Tables.Element (Revisions).Payload), "plan revision payload");
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
            Project_Row := Next_Id (Item, Tx, Projects_Table);
            Plan_Row := Next_Id (Item, Tx, Plans_Table);
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Projects_Table),
                   (Project_Row, 0, WW (Project_Key (Stored.Project)), WW ("active"), WW
                     (Pair ("name", To_String (Stored.Project.Name)) & LF &
                      Pair ("path", To_String (Stored.Project.Path)) & LF &
                      Pair ("quality_database", To_String (Stored.Project.Database_Id)) & LF &
                      Pair ("quality_project_id", Number (Stored.Project.Id))),
                    True, Projects_Table)), "store project");
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Plans_Table),
                   (Plan_Row, Project_Row, WW (Project_Key (Stored.Project)), WW ("active"), WW (""), True,
                    Plans_Table)),
                   "store plan");
         end if;
         Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Baselines_Table),
                (Baseline_Row, Project_Row, WW (Number (Stored.Baseline.Run_Id)), WW ("completed"),
                 WW (Pair ("source", To_String (Stored.Baseline.Source_Id)) & LF &
                     Pair ("policy", To_String (Stored.Baseline.Policy_Id)) & LF &
                     Pair ("toolchain", To_String (Stored.Baseline.Toolchain_Id)) & LF &
                     Pair ("assessment", To_String (Stored.Baseline.Evidence_Id)) & LF &
                     Pair ("snapshot", To_String (Stored.Baseline.Snapshot_Id))), True, Baselines_Table)),
                "store baseline");
         Stored.Plan_Id := To_Unbounded_String (Id_Image ("PLAN-", Plan_Row));
         Stored.Revision := Revision_No;
         Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Revisions_Table),
                (Revision_Row, Plan_Row, WW (To_String (Stored.Fingerprint)), WW (To_String (Stored.Review_Status)),
                 WW (Revision_Payload (Stored, Baseline_Row, Revision_No)), True, Revisions_Table)),
                "store plan revision");
         declare
            Finding_Row : Positive;
         begin
            for Finding of Stored.Findings loop
               Finding_Row := Next_Id (Item, Tx, Findings_Table);
               Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Findings_Table),
                      (Finding_Row, Revision_Row, WW (To_String (Finding.Fingerprint)),
                       WW (Improve.Model.Image (Finding.Kind)), WW (Finding_Payload (Finding)), True, Findings_Table)),
                      "store finding");
            end loop;
         end;
         declare
            First_Task_Row : constant Positive :=
              Reserve_Ids (Item, Tx, Tasks_Table, Natural (Stored.Tasks.Length));
            Assigned_Ids : String_Id_Maps.Map;
            Previous_Tasks : String_Value_Maps.Map;
            Assigned_By_Original : String_Value_Maps.Map;

            function Identity_Key
              (Category, Title, Acceptance, Finding_Set : String) return String is
              (Stable_Digest
                 (Number (Category'Length) & ":" & Category & Number (Title'Length) & ":" & Title &
                  Number (Acceptance'Length) & ":" & Acceptance & Number (Finding_Set'Length) & ":" & Finding_Set));

            procedure Index_Previous_Tasks is
               Tasks : Entity_Tables.Cursor;
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
                     Row        : constant Entity := Entity_Tables.Element (Tasks);
                     Payload    : constant String := S (Row.Payload);
                     Acceptance : Unbounded_String :=
                       To_Unbounded_String (Field_Or (Payload, "acceptance", ""));
                     Details    : Entity_Tables.Cursor :=
                       Scan_Children (Item, Tx, Task_Details_Table, Row.Id);
                     Seen_Details : String_Id_Maps.Map;
                  begin
                     Require_Text (Payload, "previous task payload");
                     while Entity_Tables.Has_Element (Details) loop
                        if Detail_Count >= Limits.Maximum_Task_Details then
                           raise Data_Error with "previous plan revision exceeds configured task-detail limit";
                        end if;
                        Detail_Count := Detail_Count + 1;
                        declare
                           Detail : constant Entity := Entity_Tables.Element (Details);
                           Name   : constant String := S (Detail.Kind);
                        begin
                           Require_Text (S (Detail.Payload), "previous task detail");
                           if Seen_Details.Contains (Name) then
                              raise Data_Error with "duplicate persisted task detail " & Name;
                           end if;
                           Seen_Details.Insert (Name, Detail.Id);
                           if Length (Acceptance) = 0 and then Name = "acceptance" then
                              Acceptance := To_Unbounded_String (S (Detail.Payload));
                           end if;
                        end;
                        Advance_Children (Item, Tx, Task_Details_Table, Row.Id, Details);
                     end loop;
                     declare
                        Key : constant String :=
                          Identity_Key
                            (S (Row.Kind), Field (Payload, "title"), To_String (Acceptance),
                             Stored_Finding_Set (Payload));
                     begin
                        if not Previous_Tasks.Contains (Key) then
                           Previous_Tasks.Insert (Key, To_Unbounded_String (Field (Payload, "draft_id")));
                        end if;
                     end;
                  end;
                  Advance_Children (Item, Tx, Tasks_Table, Positive (Previous_Revision), Tasks);
               end loop;
            end Index_Previous_Tasks;

            function Previous_Task_Id
              (Spec : Improve.Model.Task_Specification) return Ada.Strings.Unbounded.Unbounded_String is
               Key : constant String :=
                 Identity_Key
                   (To_String (Spec.Category), To_String (Spec.Title), To_String (Spec.Acceptance),
                    Stable_Digest (Pack (Spec.Finding_Keys)));
            begin
               if Previous_Tasks.Contains (Key) then
                  return Previous_Tasks.Element (Key);
               end if;
               declare
                  Legacy : Improve.Model.UString_Vectors.Vector;
               begin
                  for Link of Spec.Finding_Keys loop
                     declare Matched : Boolean := False; begin
                        for Finding of Stored.Findings loop
                           if To_String (Link) = Improve.Model.Finding_Key (Finding) then
                              Legacy.Append (Finding.Fingerprint);
                              Matched := True;
                              exit;
                           end if;
                        end loop;
                        if not Matched then Legacy.Append (Link); end if;
                     end;
                  end loop;
                  declare
                     Legacy_Key : constant String :=
                       Identity_Key
                         (To_String (Spec.Category), To_String (Spec.Title), To_String (Spec.Acceptance),
                          Stable_Digest (Pack (Legacy)));
                  begin
                     return
                       (if Previous_Tasks.Contains (Legacy_Key) then Previous_Tasks.Element (Legacy_Key)
                        else Null_Unbounded_String);
                  end;
               end;
            end Previous_Task_Id;
         begin
            Index_Previous_Tasks;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               declare
                  Original : constant Ada.Strings.Unbounded.Unbounded_String := Stored.Tasks (Index).Id;
                  Prior : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Previous_Task_Id (Stored.Tasks (Index));
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
                  Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Tasks_Table),
                         (Task_Row, Revision_Row, WW (To_String (Persisted.Category)),
                          WW (Improve.Model.Image (Persisted.Kind)), WW (Task_Payload (Persisted)), True, Tasks_Table)),
                         "store task");
                  Check
                    (Entity_Tables.Insert
                       (Tx, Item.DB, Item.Schemas (Task_Identities_Table),
                        (Next_Id (Item, Tx, Task_Identities_Table), Revision_Row,
                         WW (To_String (Persisted.Id)), WW ("active"),
                         WW (Pair ("task_row", Number (Task_Row))), True, Task_Identities_Table)),
                     "index task identity");
                  declare
                     procedure Add_Detail (Name, Value : String) is
                     begin
                        Check
                          (Entity_Tables.Insert
                             (Tx, Item.DB, Item.Schemas (Task_Details_Table),
                              (Next_Id (Item, Tx, Task_Details_Table), Task_Row, WW (Name), WW ("value"),
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
                     Check
                       (Entity_Tables.Insert
                          (Tx, Item.DB, Item.Schemas (Task_Findings_Table),
                           (Next_Id (Item, Tx, Task_Findings_Table), Task_Row, WW (To_String (Key)),
                            WW ("linked"), WW (""), True, Task_Findings_Table)),
                        "store task finding link");
                  end loop;
                  for Dependency of Persisted.Dependencies loop
                     Check
                       (Entity_Tables.Insert
                          (Tx, Item.DB, Item.Schemas (Task_Dependencies_Table),
                           (Next_Id (Item, Tx, Task_Dependencies_Table), Task_Row,
                            WW (To_String (Dependency)), WW ("required"), WW (""), True,
                            Task_Dependencies_Table)),
                        "store task dependency");
                  end loop;
               end;
            end loop;
         end;
      end;
      Database.Transactions.Commit (Tx);
      return (Plan => Stored, Existing => False);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Save;
