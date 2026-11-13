separate (Improve.Storage)
function Load_Revision
     (Item        : in out Store;
      Revision_Id : Positive;
      Limits      : Read_Limits) return Improve.Model.Plan_Revision is
      Tx : Database.Transactions.Transaction;
      Revision : Entity;
      Result : Improve.Model.Plan_Revision;
      Details : String_Value_Maps.Map;
      Dependency_Packs : String_Value_Maps.Map;
      Finding_Packs : String_Value_Maps.Map;
      Detail_Count : Natural := 0;
      Link_Count   : Natural := 0;

      procedure Append_Packed
        (Values : in out String_Value_Maps.Map;
         Key    : String;
         Value  : String) is
         Current : Unbounded_String :=
           (if Values.Contains (Key) then Values.Element (Key) else Null_Unbounded_String);
      begin
         Append (Current, Number (Value'Length) & ":" & Value);
         Values.Include (Key, Current);
      end Append_Packed;

      function Loaded_Detail (Payload : String; Task_Id : Positive; Name : String) return String is
         Inline : constant String := Field_Or (Payload, Name, "");
         Key    : constant String := Number (Task_Id) & Character'Val (0) & Name;
      begin
         if Inline /= "" then
            return Inline;
         elsif Details.Contains (Key) then
            return To_String (Details.Element (Key));
         else
            return "";
         end if;
      end Loaded_Detail;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare
         Status : constant Database.Status.Result :=
           Entity_Tables.Find
             (Tx, Item.DB, Item.Schemas (Revisions_Table),
              Physical_Key (Revisions_Table, Revision_Id), Revision);
      begin
         if Status.Code = Database.Status.Not_Found then
            raise Argument_Error with "unknown plan revision";
         end if;
         Check (Status, "read plan revision");
      end;
      declare Payload : constant String := S (Revision.Payload); begin
         Require_Payload_Limit (Payload, Limits, "plan revision payload");
         Result.Plan_Id := To_Unbounded_String (Id_Image ("PLAN-", Positive (Revision.Parent_Id)));
         Result.Revision := Positive'Value (Field (Payload, "revision"));
         Result.Project :=
           (Positive'Value (Field (Payload, "project_id")), To_Unbounded_String (Field (Payload, "project")),
            To_Unbounded_String (Field (Payload, "project_path")),
            To_Unbounded_String (Field_Or (Payload, "quality_database", "")));
         Result.Baseline :=
           (Result.Project.Id, Positive'Value (Field (Payload, "run_id")),
            To_Unbounded_String (Field (Payload, "source")), To_Unbounded_String (Field (Payload, "policy")),
            To_Unbounded_String (Field (Payload, "toolchain")), To_Unbounded_String (Field (Payload, "snapshot")));
         Result.Working_Source_Id :=
           To_Unbounded_String (Field_Or (Payload, "working_source", Field (Payload, "source")));
         Result.Planner_Id := To_Unbounded_String (Field (Payload, "planner"));
         Result.Created_At := Parse_Time (Field (Payload, "created_at"));
         Result.Fingerprint := To_Unbounded_String (S (Revision.Kind));
         Result.Review_Status := To_Unbounded_String (S (Revision.State));
      end;
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Findings_Table, Revision_Id);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if Result.Findings.Length >= Ada.Containers.Count_Type (Limits.Maximum_Findings) then
               raise Data_Error with "plan revision exceeds configured finding read limit";
            end if;
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
               Finding : Improve.Model.Finding_Reference;
            begin
               Require_Payload_Limit (Payload, Limits, "finding payload");
               Finding.Project_Id := Result.Project.Id;
               Finding.Run_Id := Result.Baseline.Run_Id;
               Finding.Indicator := Indicator_Value (Field (Payload, "indicator"));
               Finding.Rule := To_Unbounded_String (Field (Payload, "rule"));
               Finding.Level := Ada_Quality.Types.Severity'Value (Field (Payload, "severity"));
               Finding.Relative_Path := To_Unbounded_String (Field (Payload, "path"));
               Finding.Line := Natural'Value (Field (Payload, "line"));
               Finding.Fingerprint := To_Unbounded_String (S (Row.Kind));
               Finding.Semantic_Subject := To_Unbounded_String (Field (Payload, "subject"));
               Finding.Message := To_Unbounded_String (Field (Payload, "message"));
               Finding.Evidence := To_Unbounded_String (Field (Payload, "evidence"));
               Finding.Kind := Kind_Value (S (Row.State));
               Finding.Indicator_Level := Boolean'Value (Field (Payload, "indicator_level"));
               Result.Findings.Append (Finding);
            end;
            Advance_Children (Item, Tx, Findings_Table, Revision_Id, Cursor);
         end loop;
      end;
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Tasks_Table, Revision_Id);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if Result.Tasks.Length >= Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
               raise Data_Error with "plan revision exceeds configured task read limit";
            end if;
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
               Spec : Improve.Model.Task_Specification;
            begin
               Require_Payload_Limit (Payload, Limits, "task payload");
               declare
                  Child : Entity_Tables.Cursor := Scan_Children (Item, Tx, Task_Details_Table, Row.Id);
               begin
                  while Entity_Tables.Has_Element (Child) loop
                     if Detail_Count >= Limits.Maximum_Task_Details then
                        raise Data_Error with "plan revision exceeds configured task-detail read limit";
                     end if;
                     Detail_Count := Detail_Count + 1;
                     declare
                        Detail : constant Entity := Entity_Tables.Element (Child);
                        Text   : constant String := S (Detail.Payload);
                     begin
                        Require_Payload_Limit (Text, Limits, "task detail");
                        Details.Include
                          (Number (Row.Id) & Character'Val (0) & S (Detail.Kind),
                           To_Unbounded_String (Text));
                     end;
                     Advance_Children (Item, Tx, Task_Details_Table, Row.Id, Child);
                  end loop;
               end;
               declare
                  Child : Entity_Tables.Cursor := Scan_Children (Item, Tx, Task_Dependencies_Table, Row.Id);
               begin
                  while Entity_Tables.Has_Element (Child) loop
                     if Link_Count >= Limits.Maximum_Task_Links then
                        raise Data_Error with "plan revision exceeds configured task-link read limit";
                     end if;
                     Link_Count := Link_Count + 1;
                     Append_Packed
                       (Dependency_Packs, Number (Row.Id), S (Entity_Tables.Element (Child).Kind));
                     Advance_Children (Item, Tx, Task_Dependencies_Table, Row.Id, Child);
                  end loop;
               end;
               declare
                  Child : Entity_Tables.Cursor := Scan_Children (Item, Tx, Task_Findings_Table, Row.Id);
               begin
                  while Entity_Tables.Has_Element (Child) loop
                     if Link_Count >= Limits.Maximum_Task_Links then
                        raise Data_Error with "plan revision exceeds configured task-link read limit";
                     end if;
                     Link_Count := Link_Count + 1;
                     Append_Packed (Finding_Packs, Number (Row.Id), S (Entity_Tables.Element (Child).Kind));
                     Advance_Children (Item, Tx, Task_Findings_Table, Row.Id, Child);
                  end loop;
               end;
               Spec.Id := To_Unbounded_String (Field (Payload, "draft_id"));
               if Length (Spec.Id) = 0 then Spec.Id := To_Unbounded_String (Id_Image ("IMP-", Row.Id)); end if;
               Spec.Title := To_Unbounded_String (Field (Payload, "title"));
               Spec.Category := To_Unbounded_String (S (Row.Kind));
               Spec.Task_Priority := Priority_Value (Field (Payload, "priority"));
               Spec.Goal := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "goal"));
               Spec.Problem := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "problem"));
               Spec.Evidence := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "evidence"));
               Spec.Relevant_Files :=
                 Unpack
                   (Field (Payload, "files"), Limits.Maximum_Task_Links,
                    Limits.Maximum_Text_Bytes);
               Spec.Scope := To_Unbounded_String (Field (Payload, "scope"));
               Spec.Out_Of_Scope := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "out_of_scope"));
               Spec.Requirements := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "requirements"));
               Spec.Acceptance := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "acceptance"));
               Spec.Verification := To_Unbounded_String (Loaded_Detail (Payload, Row.Id, "verification"));
               Spec.Dependencies :=
                 Unpack
                   (Field_Or (Payload, "dependencies", ""), Limits.Maximum_Task_Links,
                    Limits.Maximum_Text_Bytes);
               Spec.Finding_Keys :=
                 Unpack
                   (Field_Or (Payload, "finding_keys", ""), Limits.Maximum_Task_Links,
                    Limits.Maximum_Text_Bytes);
               if Spec.Dependencies.Is_Empty and then Dependency_Packs.Contains (Number (Row.Id)) then
                  Spec.Dependencies :=
                    Unpack
                      (To_String (Dependency_Packs.Element (Number (Row.Id))),
                       Limits.Maximum_Task_Links, Limits.Maximum_Text_Bytes);
               end if;
               if Spec.Finding_Keys.Is_Empty and then Finding_Packs.Contains (Number (Row.Id)) then
                  Spec.Finding_Keys :=
                    Unpack
                      (To_String (Finding_Packs.Element (Number (Row.Id))),
                       Limits.Maximum_Task_Links, Limits.Maximum_Text_Bytes);
               end if;
               declare
                  Inline_Links : constant Natural :=
                    Natural (Spec.Relevant_Files.Length) +
                    (if Dependency_Packs.Contains (Number (Row.Id)) then 0
                     else Natural (Spec.Dependencies.Length)) +
                    (if Finding_Packs.Contains (Number (Row.Id)) then 0
                     else Natural (Spec.Finding_Keys.Length));
               begin
                  if Inline_Links > Limits.Maximum_Task_Links - Link_Count then
                     raise Data_Error with "plan revision exceeds configured task-link read limit";
                  end if;
                  Link_Count := Link_Count + Inline_Links;
               end;
               Spec.Confidence := Natural'Value (Field (Payload, "confidence"));
               Spec.Requires_Review := Boolean'Value (Field (Payload, "review"));
               Spec.Kind := Kind_Value (S (Row.State));
               Result.Tasks.Append (Spec);
            end;
            Advance_Children (Item, Tx, Tasks_Table, Revision_Id, Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      Improve.Model.Validate (Result);
      return Result;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise Data_Error with "stored plan revision is malformed";
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load_Revision;
