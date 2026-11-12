separate (Improve.Workflow_Publication.Execute)
procedure Apply_Publication_Changes (Kind : String) is
   Change    : Stores.Transaction;
   Remaining : Natural := Natural (Selected.Length);
begin
   if not Dry_Run then
      for Spec of Selected loop
         for Index of Predecessor_Indexes_Of (Spec) loop
            declare
               Mapping : Improve.Storage.Publication_Record renames Existing (Index);
               Target  : constant String := Retirement_Target (Mapping);
            begin
               if Target /= "" then
                  Tasks.Move
                    (Store, Change, To_String (Mapping.Harness_Task_Id), Target,
                     "superseded by " & To_String (Spec.Id) & " contract " & Contract_Of (Spec.Id),
                     Status => Status, Actor => Transitions.User);
                  Require_Ok (Status, "retire superseded native task");
               end if;
            end;
         end loop;
      end loop;
   end if;
   for Item of Result.Tasks loop
      if Length (Item.Harness_Id) > 0 then
         Remaining := Remaining - 1;
      end if;
   end loop;
   declare
      Count : constant Positive := Positive (Selected.Length);
      type Count_Array is array (Positive range <>) of Natural;
      type Adjacency_Array is array (Positive range <>) of Index_Vectors.Vector;
      Pending    : Count_Array (1 .. Count) := [others => 0];
      Dependents : Adjacency_Array (1 .. Count);
      Ready      : Index_Vectors.Vector;
      Head       : Positive := 1;
   begin
      for Index in 1 .. Count loop
         if Length (Result.Tasks (Index).Harness_Id) = 0 then
            for Dependency of Selected (Index).Dependencies loop
               declare
                  Identity : constant String := To_String (Dependency);
               begin
                  if Selected_Indexes.Contains (Identity) then
                     declare
                        Target : constant Positive := Selected_Indexes.Element (Identity);
                     begin
                        if Length (Result.Tasks (Target).Harness_Id) = 0 then
                           Pending (Index) := Pending (Index) + 1;
                           Dependents (Target).Append (Index);
                        end if;
                     end;
                  elsif not Is_Known (Dependency) then
                     raise Data_Error with "unknown persisted task dependency " & Identity;
                  end if;
               end;
            end loop;
            if Pending (Index) = 0 then
               Ready.Append (Index);
            end if;
         end if;
      end loop;
      while Head <= Natural (Ready.Length) loop
         declare
            Index                : constant Positive := Ready (Head);
            Spec                 : constant Improve.Model.Task_Specification := Selected (Index);
            Harness_Dependencies : Improve.Model.UString_Vectors.Vector;
            Fields               : Tasks.Field_Map;
            Id                   : Unbounded_String;
            Notes                : constant String := Native_Notes
              (Spec, Contract_Of (Spec.Id), Predecessors_Of (Spec));
         begin
            Head := Head + 1;
            for Dependency of Spec.Dependencies loop
               declare
                  Identity : constant String := To_String (Dependency);
               begin
                  if Selected_Indexes.Contains (Identity) then
                     declare
                        Target : constant Positive := Selected_Indexes.Element (Identity);
                     begin
                        if Length (Result.Tasks (Target).Harness_Id) = 0 then
                           raise Data_Error with "task dependency order cannot be resolved for publication";
                        end if;
                        Harness_Dependencies.Append (Result.Tasks (Target).Harness_Id);
                     end;
                  else
                     declare
                        Published : constant Unbounded_String := Published_Dependency (Dependency);
                     begin
                        if Length (Published) = 0 then
                           raise Data_Error with
                             "task " & To_String (Spec.Id) & " requires unpublished prerequisite " & Identity &
                             "; publish prerequisite first";
                        end if;
                        Harness_Dependencies.Append (Published);
                     end;
                  end if;
               end;
            end loop;
            Fields.Include ("title", To_String (Spec.Title));
            Fields.Include ("kind", Kind);
            Fields.Include ("priority", Harness_Priority (Spec.Task_Priority));
            Fields.Include ("acceptance", To_String (Spec.Acceptance));
            Fields.Include ("notes", Notes);
            if not Harness_Dependencies.Is_Empty then
               Fields.Include ("depends_on", Join (Harness_Dependencies));
            end if;
            Tasks.Create
              (Store, Change, Fields, "improve", To_String (Result.Tasks (Index).Origin), Id, Status);
            Require_Ok (Status, "create native harness task " & To_String (Spec.Id));
            Result.Tasks (Index).Harness_Id := Id;
            Result.Tasks (Index).State := To_Unbounded_String ("candidate");
            Remaining := Remaining - 1;
            for Dependent of Dependents (Index) loop
               Pending (Dependent) := Pending (Dependent) - 1;
               if Pending (Dependent) = 0 then
                  Ready.Append (Dependent);
               end if;
            end loop;
         end;
      end loop;
   end;
   if Remaining > 0 then
      raise Data_Error with "task dependency order cannot be resolved for publication";
   end if;
   if Stores.Change_Count (Change) > 0 and then not Dry_Run then
      Stores.Commit (Store, Change, Status);
      Require_Ok (Status, "commit native harness tasks");
   end if;
   if not Dry_Run then
      for Index in 1 .. Natural (Result.Tasks.Length) loop
         Result.Tasks (Index).State :=
           To_Unbounded_String (Tasks.State_Of (Store, To_String (Result.Tasks (Index).Harness_Id)));
      end loop;
   end if;
end Apply_Publication_Changes;
