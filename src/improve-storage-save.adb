separate (Improve.Storage)
function Save (Item : in out Store; Value : Improve.Model.Plan_Revision) return Save_Result is
      Tx : Database.Transactions.Transaction;
      Stored : Improve.Model.Plan_Revision := Value;
      Existing_Revision : Natural;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for writing";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Existing_Revision := Find_Revision (Item, Tx, To_String (Value.Fingerprint));
      if Existing_Revision > 0 then
         Database.Transactions.Rollback (Tx);
         declare
            Task_Count : constant Positive := Positive'Max (1, Natural (Value.Tasks.Length));
            Link_Count : Natural := 0;
            Text_Count : Natural :=
              Natural'Max
                (Default_Read_Limits.Maximum_Text_Bytes,
                 Revision_Payload (Value, 1, 1)'Length);

            procedure Include_Text (Text : String) is
            begin
               Text_Count := Natural'Max (Text_Count, Text'Length);
            end Include_Text;
         begin
            for Finding of Value.Findings loop
               Include_Text (Finding_Payload (Finding));
            end loop;
            for Spec of Value.Tasks loop
               Link_Count :=
                 Link_Count + Natural (Spec.Relevant_Files.Length) +
                 Natural (Spec.Finding_Keys.Length) + Natural (Spec.Dependencies.Length);
               Include_Text (Task_Payload (Spec));
               Include_Text (To_String (Spec.Goal));
               Include_Text (To_String (Spec.Problem));
               Include_Text (To_String (Spec.Evidence));
               Include_Text (To_String (Spec.Out_Of_Scope));
               Include_Text (To_String (Spec.Requirements));
               Include_Text (To_String (Spec.Acceptance));
               Include_Text (To_String (Spec.Verification));
            end loop;
            return
              (Plan =>
                 Load
                   (Item, "@revision:" & Number (Existing_Revision),
                    Limits =>
                      (Maximum_Findings     => Positive'Max (1, Natural (Value.Findings.Length)),
                       Maximum_Tasks        => Task_Count,
                       Maximum_Task_Details => 7 * Task_Count,
                       Maximum_Task_Links   => Positive'Max (1, Link_Count),
                       Maximum_History      => Default_Read_Limits.Maximum_History,
                       Maximum_Text_Bytes   => Positive'Max (1, Text_Count))),
               Existing => True);
         end;
      end if;
      Stored.Created_At := Ada.Calendar.Clock;
      declare
         Project_Row  : constant Positive := Next_Id (Item, Tx, Projects_Table);
         Baseline_Row : constant Positive := Next_Id (Item, Tx, Baselines_Table);
         Plan_Row     : Positive := Next_Id (Item, Tx, Plans_Table);
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
            declare Revisions : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Plan_Row);
            begin
               while Entity_Tables.Has_Element (Revisions) loop
                  if Entity_Tables.Element (Revisions).Parent_Id = Plan_Row then
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
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Projects_Table),
                   (Project_Row, 0, WW (Project_Key (Stored.Project)), WW ("active"), WW
                     (Pair ("name", To_String (Stored.Project.Name)) & LF &
                      Pair ("path", To_String (Stored.Project.Path)) & LF &
                      Pair ("quality_database", To_String (Stored.Project.Database_Id))),
                    True, Projects_Table)), "store project");
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Plans_Table),
                   (Plan_Row, Stored.Project.Id, WW (Project_Key (Stored.Project)), WW ("active"), WW (""), True,
                    Plans_Table)),
                   "store plan");
         end if;
         Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Baselines_Table),
                (Baseline_Row, Stored.Project.Id, WW (Number (Stored.Baseline.Run_Id)), WW ("completed"),
                 WW (Pair ("source", To_String (Stored.Baseline.Source_Id)) & LF &
                     Pair ("policy", To_String (Stored.Baseline.Policy_Id)) & LF &
                     Pair ("toolchain", To_String (Stored.Baseline.Toolchain_Id)) & LF &
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
            Original_Ids : Improve.Model.UString_Vectors.Vector;
            Assigned_Ids : Improve.Model.UString_Vectors.Vector;
            Previous_Tasks : String_Value_Maps.Map;

            function Identity_Key
              (Category, Title, Acceptance, Finding_Set : String) return String is
              (Stable_Digest
                 (Number (Category'Length) & ":" & Category & Number (Title'Length) & ":" & Title &
                  Number (Acceptance'Length) & ":" & Acceptance & Number (Finding_Set'Length) & ":" & Finding_Set));

            procedure Index_Previous_Tasks is
               Tasks : Entity_Tables.Cursor;
            begin
               if Previous_Revision = 0 then
                  return;
               end if;
               Tasks := Scan_Children (Item, Tx, Tasks_Table, Positive (Previous_Revision));
               while Entity_Tables.Has_Element (Tasks) loop
                  declare
                     Row        : constant Entity := Entity_Tables.Element (Tasks);
                     Payload    : constant String := S (Row.Payload);
                     Acceptance : Unbounded_String :=
                       To_Unbounded_String (Field_Or (Payload, "acceptance", ""));
                     Details    : Entity_Tables.Cursor :=
                       Scan_Children (Item, Tx, Task_Details_Table, Row.Id);
                  begin
                     while Length (Acceptance) = 0 and then Entity_Tables.Has_Element (Details) loop
                        if S (Entity_Tables.Element (Details).Kind) = "acceptance" then
                           Acceptance := To_Unbounded_String (S (Entity_Tables.Element (Details).Payload));
                        end if;
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
               return (if Previous_Tasks.Contains (Key) then Previous_Tasks.Element (Key) else Null_Unbounded_String);
            end Previous_Task_Id;
         begin
            Index_Previous_Tasks;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               Original_Ids.Append (Stored.Tasks (Index).Id);
               declare
                  Prior : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Previous_Task_Id (Stored.Tasks (Index));
                  Identity : constant Ada.Strings.Unbounded.Unbounded_String :=
                    (if Length (Prior) > 0 and then not Assigned_Ids.Contains (Prior) then Prior
                     else To_Unbounded_String (Id_Image ("IMP-", First_Task_Row + Index - 1)));
               begin
                  Stored.Tasks (Index).Id := Identity;
                  Assigned_Ids.Append (Identity);
               end;
            end loop;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               declare
                  Task_Row  : constant Positive := First_Task_Row + Index - 1;
                  Persisted : Improve.Model.Task_Specification := Stored.Tasks (Index);
                  Translated : Improve.Model.UString_Vectors.Vector;
               begin
                  for Dependency of Persisted.Dependencies loop
                     declare Found : Boolean := False; begin
                        for Target in 1 .. Natural (Original_Ids.Length) loop
                           if Original_Ids (Target) = Dependency then
                              Translated.Append (Stored.Tasks (Target).Id);
                              Found := True;
                              exit;
                           end if;
                        end loop;
                        if not Found then
                           raise Data_Error with "task dependency is absent from the persisted plan";
                        end if;
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
         declare Operation_Row : constant Positive := Next_Id (Item, Tx, Operations_Table); begin
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Operations_Table),
                   (Operation_Row, Revision_Row, WW ("plan:" & To_String (Stored.Fingerprint)), WW ("committed"),
                    WW (Pair ("plan_id", To_String (Stored.Plan_Id))), True, Operations_Table)),
                   "journal plan operation");
         end;
      end;
      Database.Transactions.Commit (Tx);
      return (Plan => Stored, Existing => False);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Save;
