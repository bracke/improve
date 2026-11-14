separate (Improve.Workflow_Publication)
function Execute
  (Project_Directory : String;
   Plan              : Improve.Model.Plan_Revision;
   Requested_Kind    : String;
   Existing          : Improve.Storage.Publication_Vectors.Vector :=
     Improve.Storage.Publication_Vectors.Empty_Vector;
   Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
     Improve.Model.UString_Vectors.Empty_Vector;
   Existing_Only     : Boolean := False;
   Dry_Run           : Boolean := False) return Publication_Result is
   Store  : Stores.Store;
   Report : Stores.Recovery_Report;
   Status : Errors.Error_Info;
   Result : Publication_Result;
   Prepared : constant Prepared_Publication := Build_Preflight (Plan, Selected_Task_Ids);
   Selected : Improve.Model.Task_Vectors.Vector renames Prepared.Selected;
   Contracts : Improve.Model.Task_Contract_Binding_Vectors.Vector renames Prepared.Contracts;
   Native_By_Origin : Native_Origin_Maps.Map;
   Contract_By_Task  : Native_Origin_Maps.Map;
   Plan_Indexes      : String_Index_Maps.Map;
   Selected_Indexes  : String_Index_Maps.Map;
   Current_Mappings  : String_Index_Maps.Map;
   Existing_Heads    : String_Index_Maps.Map;
   type Natural_Array is array (Natural range <>) of Natural;
   Existing_Next     : Natural_Array (1 .. Natural (Existing.Length)) := [others => 0];

   procedure Build_Indexes is
   begin
      for Index in 1 .. Natural (Plan.Tasks.Length) loop
         declare Identity : constant String := To_String (Plan.Tasks (Index).Id); begin
            if Plan_Indexes.Contains (Identity) then
               raise Data_Error with "duplicate task identity " & Identity;
            end if;
            Plan_Indexes.Insert (Identity, Index);
         end;
      end loop;
      for Index in 1 .. Natural (Selected.Length) loop
         Selected_Indexes.Insert (To_String (Selected (Index).Id), Index);
      end loop;
      for Binding of Contracts loop
         Contract_By_Task.Insert (To_String (Binding.Task_Id), Binding.Fingerprint);
      end loop;
      for Index in 1 .. Natural (Existing.Length) loop
         declare
            Identity : constant String := To_String (Existing (Index).Improve_Task_Id);
         begin
            Existing_Next (Index) :=
              (if Existing_Heads.Contains (Identity) then Existing_Heads.Element (Identity) else 0);
            Existing_Heads.Include (Identity, Index);
            if Contract_By_Task.Contains (Identity) and then
              Existing (Index).Contract = Contract_By_Task.Element (Identity)
            then
               if Current_Mappings.Contains (Identity) then
                  declare
                     Current : Improve.Storage.Publication_Record renames
                       Existing (Current_Mappings.Element (Identity));
                  begin
                     if Existing (Index).Plan_Revision > Current.Plan_Revision then
                        Current_Mappings.Replace (Identity, Index);
                     elsif Existing (Index).Plan_Revision = Current.Plan_Revision and then
                       (Existing (Index).Harness_Task_Id /= Current.Harness_Task_Id or else
                        Existing (Index).Origin /= Current.Origin)
                     then
                        raise Data_Error with
                          "conflicting publication mappings for current task contract " & Identity;
                     end if;
                  end;
               else
                  Current_Mappings.Insert (Identity, Index);
               end if;
            end if;
         end;
      end loop;
   end Build_Indexes;

   procedure Index_Native_Tasks is
   begin
      for Id of Tasks.List (Store) loop
         declare Definition : Records.Item; begin
            Tasks.Definition (Store, Id, Definition, Status);
            Require_Ok (Status, "read listed native task " & Id);
            if Records.Get (Definition, "created_by") = "improve" then
               declare Origin : constant String := Records.Get (Definition, "origin"); begin
                  if Origin /= "" then
                     if Native_By_Origin.Contains (Origin) and then
                       To_String (Native_By_Origin.Element (Origin)) /= Id
                     then
                        raise Data_Error with "duplicate native task origin " & Origin;
                     end if;
                     Native_By_Origin.Include (Origin, To_Unbounded_String (Id));
                  end if;
               end;
            end if;
         end;
      end loop;
   end Index_Native_Tasks;

   function Existing_By_Origin
     (Origin       : String;
      Spec         : Improve.Model.Task_Specification;
      Kind         : String;
      Binding      : String;
      Predecessors : Improve.Model.UString_Vectors.Vector) return String is
   begin
      if not Native_By_Origin.Contains (Origin) then return ""; end if;
      declare
         Id         : constant String := To_String (Native_By_Origin.Element (Origin));
         Definition : Records.Item;
      begin
         Tasks.Definition (Store, Id, Definition, Status);
         Require_Ok (Status, "read native task by Improve origin");
         Require_Compatible_Definition (Definition, Spec, Kind, Origin, Binding, Predecessors);
         return Id;
      end;
   end Existing_By_Origin;

   function Is_Selected (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
     (Selected_Indexes.Contains (To_String (Task_Id)));

   function Is_Known (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
     (Plan_Indexes.Contains (To_String (Task_Id)));

   function Contract_Of (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return String is
     (if Contract_By_Task.Contains (To_String (Task_Id))
      then To_String (Contract_By_Task.Element (To_String (Task_Id)))
      else "");

   function Is_Predecessor
     (Mapping : Improve.Storage.Publication_Record;
      Spec    : Improve.Model.Task_Specification) return Boolean is
      (Mapping.Improve_Task_Id = Spec.Id and then
      To_String (Mapping.Contract) /= Contract_Of (Spec.Id) and then
      Mapping.Plan_Revision < Plan.Revision);

   function Predecessor_Indexes_Of
     (Spec : Improve.Model.Task_Specification) return Index_Vectors.Vector is
      Values : Index_Vectors.Vector;
      Index  : Natural :=
        (if Existing_Heads.Contains (To_String (Spec.Id))
         then Existing_Heads.Element (To_String (Spec.Id))
         else 0);
   begin
      while Index > 0 loop
         if Is_Predecessor (Existing (Index), Spec) then
            Values.Append (Positive (Index));
         end if;
         Index := Existing_Next (Index);
      end loop;
      return Values;
   end Predecessor_Indexes_Of;

   function Predecessors_Of
     (Spec : Improve.Model.Task_Specification) return Improve.Model.UString_Vectors.Vector is
      Values : Improve.Model.UString_Vectors.Vector;
      Seen   : String_Sets.Set;
   begin
      for Index of Predecessor_Indexes_Of (Spec) loop
         if not Seen.Contains (To_String (Existing (Index).Harness_Task_Id)) then
            Seen.Insert (To_String (Existing (Index).Harness_Task_Id));
            Values.Append (Existing (Index).Harness_Task_Id);
         end if;
      end loop;
      return Values;
   end Predecessors_Of;

   function Has_Current_Mapping (Spec : Improve.Model.Task_Specification) return Boolean is
     (Current_Mappings.Contains (To_String (Spec.Id)));

   function Retirement_Target (Mapping : Improve.Storage.Publication_Record) return String is
      Definition : Records.Item;
      Current    : Unbounded_String;
      Core       : Unbounded_String;
      Target     : Unbounded_String;
   begin
      Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
      Require_Ok (Status, "read superseded native task " & To_String (Mapping.Harness_Task_Id));
      if Records.Get (Definition, "created_by") /= "improve" or else
        Records.Get (Definition, "origin") /= To_String (Mapping.Origin)
      then
         raise Data_Error with "superseded native task has invalid Improve provenance";
      end if;
      Current := To_Unbounded_String (Tasks.State_Of (Store, To_String (Mapping.Harness_Task_Id)));
      Core := To_Unbounded_String (Tasks.Counts_As (Store, To_String (Current)));
      if To_String (Core) in "running" | "verification" then
         raise Data_Error with
           "cannot replace logical task " & To_String (Mapping.Improve_Task_Id) & " while native predecessor " &
           To_String (Mapping.Harness_Task_Id) & " is " & To_String (Current);
      elsif To_String (Core) = "candidate" then
         Target := To_Unbounded_String ("rejected");
      elsif To_String (Core) in "accepted" | "blocked" | "failed" then
         Target := To_Unbounded_String ("cancelled");
      elsif To_String (Core) not in "complete" | "cancelled" | "rejected" then
         raise Data_Error with
           "cannot safely retire native predecessor " & To_String (Mapping.Harness_Task_Id) &
           " from unrecognized state " & To_String (Current);
      end if;
      if Length (Target) > 0 then
         Transitions.Check
           (Tasks.Lifecycle_Of (Store), To_String (Mapping.Harness_Task_Id), To_String (Current),
            To_String (Target), Transitions.Ordinary_Only, Status);
         Require_Ok (Status, "authorize retirement of superseded native task");
      end if;
      return To_String (Target);
   end Retirement_Target;

   function Published_Dependency
     (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Ada.Strings.Unbounded.Unbounded_String is
   begin
      if Current_Mappings.Contains (To_String (Task_Id)) then
         declare
            Mapping : Improve.Storage.Publication_Record renames
              Existing (Current_Mappings.Element (To_String (Task_Id)));
            Definition : Records.Item;
         begin
            Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
            Require_Ok (Status, "read prerequisite harness task " & To_String (Task_Id));
            if Records.Get (Definition, "created_by") /= "improve" or else
              Records.Get (Definition, "origin") /= To_String (Mapping.Origin)
            then
               raise Data_Error with "stored prerequisite mapping has invalid harness provenance";
            end if;
            return Mapping.Harness_Task_Id;
         end;
      end if;
      return Null_Unbounded_String;
   end Published_Dependency;

   procedure Prepare_Publication is
   begin
      if not Stores.Is_Initialized (Project_Directory) then
         raise Dependency_Error with "model_runner project state is not initialized: " & Project_Directory;
      end if;
      if Dry_Run or else Existing_Only then
         Stores.Open_To_Read (Store, Project_Directory, Status);
      else
         Stores.Open (Store, Project_Directory, Report, Status);
      end if;
      Require_Ok (Status, "open model_runner project state");
      Index_Native_Tasks;
   end Prepare_Publication;

   procedure Validate_Replacement_Closure is separate;

   procedure Resolve_Existing_Publications (Kind : String) is separate;

   procedure Validate_Existing_Dependencies is
   begin
      for Index in 1 .. Natural (Result.Tasks.Length) loop
         if Length (Result.Tasks (Index).Harness_Id) > 0 then
            declare
               Spec         : constant Improve.Model.Task_Specification := Selected (Index);
               Definition   : Records.Item;
               Dependencies : Improve.Model.UString_Vectors.Vector;
            begin
               for Dependency of Spec.Dependencies loop
                  declare
                     Identity : constant String := To_String (Dependency);
                  begin
                     if Selected_Indexes.Contains (Identity) then
                        declare
                           Other : Published_Task renames
                             Result.Tasks (Selected_Indexes.Element (Identity));
                        begin
                           if Length (Other.Harness_Id) = 0 then
                              raise Data_Error with
                                "existing native task depends on unpublished selected task " & Identity;
                           end if;
                           Dependencies.Append (Other.Harness_Id);
                        end;
                     else
                        declare
                           Published : constant Unbounded_String := Published_Dependency (Dependency);
                        begin
                           if Length (Published) = 0 then
                              raise Data_Error with
                                "existing native task has unpublished prerequisite " & Identity;
                           end if;
                           Dependencies.Append (Published);
                        end;
                     end if;
                  end;
               end loop;
               Tasks.Definition (Store, To_String (Result.Tasks (Index).Harness_Id), Definition, Status);
               Require_Ok (Status, "read complete native task definition " & To_String (Spec.Id));
               if Records.Get (Definition, "depends_on") /= Join (Dependencies) then
                  raise Data_Error with
                    "native dependency definition differs from the Improve contract for " & To_String (Spec.Id);
               end if;
            end;
         end if;
      end loop;
   end Validate_Existing_Dependencies;

   procedure Apply_Publication_Changes (Kind : String) is separate;
begin
   Build_Indexes;
   Prepare_Publication;
   declare Kind : constant String := Resolve_Kind (Store, Requested_Kind); begin
      Result.Task_Kind := To_Unbounded_String (Kind);
      Validate_Replacement_Closure;
      Resolve_Existing_Publications (Kind);
      Validate_Existing_Dependencies;
      if Existing_Only then
         Stores.Close (Store);
         return Result;
      end if;
      Apply_Publication_Changes (Kind);
   end;
   Stores.Close (Store);
   return Result;
exception
   when others =>
      if Stores.Is_Open (Store) then Stores.Close (Store); end if;
      raise;
end Execute;
