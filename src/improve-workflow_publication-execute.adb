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

   procedure Index_Native_Tasks is
   begin
      for Id of Tasks.List (Store) loop
         declare Definition : Records.Item; begin
            Tasks.Definition (Store, Id, Definition, Status);
            if Errors.Is_Ok (Status) and then Records.Get (Definition, "created_by") = "improve" then
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
     (for some Spec of Selected => Spec.Id = Task_Id);

   function Is_Known (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
     (for some Spec of Plan.Tasks => Spec.Id = Task_Id);

   function Contract_Of (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return String is
   begin
      return Improve.Model.Effective_Task_Contract (Contracts, Task_Id);
   exception
      when Data_Error => return "";
   end Contract_Of;

   function Is_Predecessor
     (Mapping : Improve.Storage.Publication_Record;
      Spec    : Improve.Model.Task_Specification) return Boolean is
      (Mapping.Improve_Task_Id = Spec.Id and then
      To_String (Mapping.Contract) /= Improve.Model.Effective_Task_Contract (Contracts, Spec.Id) and then
      Mapping.Plan_Revision < Plan.Revision);

   function Predecessors_Of
     (Spec : Improve.Model.Task_Specification) return Improve.Model.UString_Vectors.Vector is
      Values : Improve.Model.UString_Vectors.Vector;
   begin
      for Mapping of Existing loop
         if Is_Predecessor (Mapping, Spec) and then not Values.Contains (Mapping.Harness_Task_Id) then
            Values.Append (Mapping.Harness_Task_Id);
         end if;
      end loop;
      return Values;
   end Predecessors_Of;

   function Has_Current_Mapping (Spec : Improve.Model.Task_Specification) return Boolean is
      Binding : constant String := Improve.Model.Effective_Task_Contract (Contracts, Spec.Id);
   begin
      return
        (for some Mapping of Existing =>
           Mapping.Improve_Task_Id = Spec.Id and then To_String (Mapping.Contract) = Binding);
   end Has_Current_Mapping;

   function Depends_On_Any
     (Spec    : Improve.Model.Task_Specification;
      Targets : Improve.Model.UString_Vectors.Vector;
      Trail   : Improve.Model.UString_Vectors.Vector := Improve.Model.UString_Vectors.Empty_Vector)
      return Boolean is
      Next_Trail : Improve.Model.UString_Vectors.Vector := Trail;
   begin
      if Trail.Contains (Spec.Id) then return False; end if;
      Next_Trail.Append (Spec.Id);
      for Dependency of Spec.Dependencies loop
         if Targets.Contains (Dependency) then return True; end if;
         for Candidate of Plan.Tasks loop
            if Candidate.Id = Dependency and then Depends_On_Any (Candidate, Targets, Next_Trail) then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Depends_On_Any;

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
      for Mapping of Existing loop
         if Mapping.Improve_Task_Id = Task_Id and then
           To_String (Mapping.Contract) = Contract_Of (Task_Id)
         then
            declare Definition : Records.Item; begin
               Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
               Require_Ok (Status, "read prerequisite harness task " & To_String (Task_Id));
               if Records.Get (Definition, "created_by") /= "improve" or else
                 Records.Get (Definition, "origin") /= To_String (Mapping.Origin)
               then
                  raise Data_Error with "stored prerequisite mapping has invalid harness provenance";
               end if;
            end;
            return Mapping.Harness_Task_Id;
         end if;
      end loop;
      return Null_Unbounded_String;
   end Published_Dependency;

   procedure Prepare_Publication is
   begin
      if not Stores.Is_Initialized (Project_Directory) then
         raise Dependency_Error with "model_runner project state is not initialized: " & Project_Directory;
      end if;
      if Dry_Run then
         Stores.Open_To_Read (Store, Project_Directory, Status);
      else
         Stores.Open (Store, Project_Directory, Report, Status);
      end if;
      Require_Ok (Status, "open model_runner project state");
      Index_Native_Tasks;
   end Prepare_Publication;

   procedure Validate_Replacement_Closure is
      Replaced : Improve.Model.UString_Vectors.Vector;
   begin
      for Spec of Selected loop
         if not Has_Current_Mapping (Spec) and then not Predecessors_Of (Spec).Is_Empty then
            Replaced.Append (Spec.Id);
         end if;
      end loop;
      if Replaced.Is_Empty then
         return;
      end if;
      for Spec of Plan.Tasks loop
         if not Is_Selected (Spec.Id) and then not Has_Current_Mapping (Spec) and then
           Depends_On_Any (Spec, Replaced)
         then
            for Mapping of Existing loop
               if Is_Predecessor (Mapping, Spec) then
                  declare
                     Definition   : Records.Item;
                     Native_State : constant String := Tasks.State_Of
                       (Store, To_String (Mapping.Harness_Task_Id));
                     Core_State   : constant String := Tasks.Counts_As (Store, Native_State);
                  begin
                     Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
                     Require_Ok (Status, "read downstream native task " & To_String (Mapping.Harness_Task_Id));
                     if Records.Get (Definition, "created_by") /= "improve" or else
                       Records.Get (Definition, "origin") /= To_String (Mapping.Origin)
                     then
                        raise Data_Error with "downstream native task has invalid Improve provenance";
                     elsif Core_State not in "complete" | "cancelled" | "rejected" then
                        raise Data_Error with
                          "selective replacement would strand published dependent " & To_String (Spec.Id) &
                          " (" & To_String (Mapping.Harness_Task_Id) & " is " & Native_State &
                          "); publish the complete plan so its dependency can be replaced atomically";
                     end if;
                  end;
               end if;
            end loop;
         end if;
      end loop;
   end Validate_Replacement_Closure;

   procedure Resolve_Existing_Publications (Kind : String) is
   begin
      for Spec of Selected loop
         declare
            Contract     : constant Unbounded_String :=
              To_Unbounded_String (Improve.Model.Effective_Task_Contract (Contracts, Spec.Id));
            Origin       : Unbounded_String := To_Unbounded_String (Origin_Of (Plan, Spec, To_String (Contract)));
            Harness_Id   : Unbounded_String;
            Was_Mapped   : Boolean := False;
            Predecessors : constant Improve.Model.UString_Vectors.Vector := Predecessors_Of (Spec);
         begin
            for Mapping of Existing loop
               if Is_Predecessor (Mapping, Spec) then
                  declare
                     Target : constant String := Retirement_Target (Mapping);
                     pragma Unreferenced (Target);
                  begin
                     null;
                  end;
               end if;
            end loop;
            for Mapping of Existing loop
               if Mapping.Improve_Task_Id = Spec.Id and then Mapping.Contract = Contract then
                  declare
                     Definition : Records.Item;
                  begin
                     Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
                     Require_Ok (Status, "read previously published harness task " & To_String (Spec.Id));
                     if Mapping.Origin /= Origin then
                        raise Data_Error with "stored publication mapping has an incompatible stable origin";
                     end if;
                     Require_Compatible_Definition
                       (Definition, Spec, Kind, To_String (Mapping.Origin), To_String (Contract), Predecessors);
                  end;
                  Origin := Mapping.Origin;
                  Harness_Id := Mapping.Harness_Task_Id;
                  Was_Mapped := True;
                  exit;
               end if;
            end loop;
            if not Was_Mapped then
               Harness_Id := To_Unbounded_String
                 (Existing_By_Origin (To_String (Origin), Spec, Kind, To_String (Contract), Predecessors));
            end if;
            Result.Tasks.Append
              (Published_Task'
                 (Improve_Id => Spec.Id,
                  Harness_Id => Harness_Id,
                  Origin     => Origin,
                  Contract   => Contract,
                  State      => To_Unbounded_String
                    (if Length (Harness_Id) = 0 then (if Dry_Run then "candidate" else "")
                     else Tasks.State_Of (Store, To_String (Harness_Id))),
                  Recovered  => Length (Harness_Id) > 0));
         end;
      end loop;
   end Resolve_Existing_Publications;

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
                     Found : Boolean := False;
                  begin
                     for Other of Result.Tasks loop
                        if Other.Improve_Id = Dependency then
                           Found := True;
                           if Length (Other.Harness_Id) = 0 then
                              raise Data_Error with
                                "existing native task depends on unpublished selected task " &
                                To_String (Dependency);
                           end if;
                           Dependencies.Append (Other.Harness_Id);
                           exit;
                        end if;
                     end loop;
                     if not Found then
                        declare
                           Published : constant Unbounded_String := Published_Dependency (Dependency);
                        begin
                           if Length (Published) = 0 then
                              raise Data_Error with
                                "existing native task has unpublished prerequisite " & To_String (Dependency);
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

   procedure Apply_Publication_Changes (Kind : String) is
      Change    : Stores.Transaction;
      Remaining : Natural := Natural (Selected.Length);
      Progress  : Boolean;
   begin
      if not Dry_Run then
         for Spec of Selected loop
            for Mapping of Existing loop
               if Is_Predecessor (Mapping, Spec) then
                  declare
                     Target : constant String := Retirement_Target (Mapping);
                  begin
                     if Target /= "" then
                        Tasks.Move
                          (Store, Change, To_String (Mapping.Harness_Task_Id), Target,
                           "superseded by " & To_String (Spec.Id) & " contract " &
                             Improve.Model.Effective_Task_Contract (Contracts, Spec.Id),
                           Status => Status, Actor => Transitions.User);
                        Require_Ok (Status, "retire superseded native task");
                     end if;
                  end;
               end if;
            end loop;
         end loop;
      end if;
      for Item of Result.Tasks loop
         if Length (Item.Harness_Id) > 0 then
            Remaining := Remaining - 1;
         end if;
      end loop;
      while Remaining > 0 loop
         Progress := False;
         for Index in 1 .. Natural (Selected.Length) loop
            if Length (Result.Tasks (Index).Harness_Id) = 0 then
               declare
                  Spec                 : constant Improve.Model.Task_Specification := Selected (Index);
                  Ready                : Boolean := True;
                  Harness_Dependencies : Improve.Model.UString_Vectors.Vector;
               begin
                  for Dependency of Spec.Dependencies loop
                     declare
                        Found : Boolean := False;
                     begin
                        for Other in 1 .. Natural (Result.Tasks.Length) loop
                           if Result.Tasks (Other).Improve_Id = Dependency then
                              Found := True;
                              if Length (Result.Tasks (Other).Harness_Id) = 0 then
                                 Ready := False;
                              else
                                 Harness_Dependencies.Append (Result.Tasks (Other).Harness_Id);
                              end if;
                              exit;
                           end if;
                        end loop;
                        if not Found then
                           if not Is_Known (Dependency) then
                              raise Data_Error with
                                "unknown persisted task dependency " & To_String (Dependency);
                           end if;
                           declare
                              Published : constant Unbounded_String := Published_Dependency (Dependency);
                           begin
                              if Length (Published) = 0 then
                                 raise Data_Error with
                                   "task " & To_String (Spec.Id) & " requires unpublished prerequisite " &
                                   To_String (Dependency) & "; publish prerequisite first";
                              end if;
                              Harness_Dependencies.Append (Published);
                           end;
                        end if;
                     end;
                  end loop;
                  if Ready then
                     declare
                        Fields : Tasks.Field_Map;
                        Id     : Unbounded_String;
                        Notes  : constant String := Native_Notes
                          (Spec, Improve.Model.Effective_Task_Contract (Contracts, Spec.Id),
                           Predecessors_Of (Spec));
                     begin
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
                        Progress := True;
                     end;
                  end if;
               end;
            end if;
         end loop;
         if not Progress and then Remaining > 0 then
            raise Data_Error with "task dependency order cannot be resolved for publication";
         end if;
      end loop;
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
begin
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
