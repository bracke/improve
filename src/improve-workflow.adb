with Ada.Containers;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;
with Model_Runner.Framework.Transitions;

package body Improve.Workflow is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   package Errors renames Model_Runner.Errors;
   package Records renames Model_Runner.Framework.Records;
   package Stores renames Model_Runner.Framework.Stores;
   package Tasks renames Model_Runner.Framework.Tasks;
   package Transitions renames Model_Runner.Framework.Transitions;

   function Detail (Status : Errors.Error_Info) return String is
      Name   : constant String := Errors.Text_Of (Status, "name");
      Reason : constant String := Errors.Text_Of (Status, "detail");
   begin
      return Errors.Diagnostic_Code (Status.Code) &
        (if Name = "" then "" else " " & Name) &
        (if Reason = "" then "" else ": " & Reason);
   end Detail;

   procedure Require_Ok (Status : Errors.Error_Info; Context : String) is
   begin
      if Errors.Is_Error (Status) then raise Data_Error with Context & ": " & Detail (Status); end if;
   end Require_Ok;

   function Resolve_Kind (Store : Stores.Store; Requested : String) return String is
      Kinds : constant Model_Runner.Framework.Name_Lists.Vector := Tasks.Kinds (Store);
   begin
      if Requested /= "auto" then
         if not Kinds.Contains (Requested) then
            raise Data_Error with "configured remediation task kind is not available: " & Requested;
         end if;
         return Requested;
      elsif Kinds.Length = 1 then
         return Kinds.First_Element;
      elsif Kinds.Is_Empty then
         raise Data_Error with "target project defines no task kind";
      else
         raise Data_Error with "task_kind=auto is ambiguous; configure one of the target project's task kinds";
      end if;
   end Resolve_Kind;

   function Origin_Of
     (Plan : Improve.Model.Plan_Revision;
      Spec : Improve.Model.Task_Specification) return String is
     ("improve:" & Stable_Digest (To_String (Plan.Project.Path)) & ":task:" & To_String (Spec.Id) &
      ":contract:" & Improve.Model.Task_Contract_Fingerprint (Spec));

   function Harness_Priority (Value : Improve.Model.Priority) return String is
     (case Value is
         when Improve.Model.Critical_Priority => "100",
         when Improve.Model.High_Priority => "75",
         when Improve.Model.Normal_Priority => "50",
         when Improve.Model.Low_Priority => "25");

   function Join (Values : Improve.Model.UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         if Length (Result) > 0 then Append (Result, ", "); end if;
         Append (Result, Value);
      end loop;
      return To_String (Result);
   end Join;

   function Native_Notes
     (Spec         : Improve.Model.Task_Specification;
      Predecessors : Improve.Model.UString_Vectors.Vector) return String is
     ("Improve task: " & To_String (Spec.Id) & ASCII.LF &
      "Contract: " & Improve.Model.Task_Contract_Fingerprint (Spec) & ASCII.LF &
      (if Predecessors.Is_Empty then "" else "Supersedes: " & Join (Predecessors) & ASCII.LF) &
      "Goal: " & To_String (Spec.Goal) & ASCII.LF &
      "Problem: " & To_String (Spec.Problem) & ASCII.LF &
      "Evidence:" & ASCII.LF & To_String (Spec.Evidence) & ASCII.LF &
      "Relevant files: " & Join (Spec.Relevant_Files) & ASCII.LF &
      "Scope: " & To_String (Spec.Scope) & ASCII.LF &
      "Out of scope: " & To_String (Spec.Out_Of_Scope) & ASCII.LF &
      "Requirements: " & To_String (Spec.Requirements) & ASCII.LF &
      "Verification: " & To_String (Spec.Verification));

   procedure Require_Compatible_Definition
     (Value  : Records.Item;
      Spec   : Improve.Model.Task_Specification;
      Kind   : String;
      Origin : String;
      Predecessors : Improve.Model.UString_Vectors.Vector) is
   begin
      if Records.Get (Value, "created_by") /= "improve" or else Records.Get (Value, "origin") /= Origin then
         raise Data_Error with "native task provenance does not match Improve publication identity";
      end if;
      if Records.Get (Value, "title") /= To_String (Spec.Title) or else
        Records.Get (Value, "kind") /= Kind or else
        Records.Get (Value, "priority") /= Harness_Priority (Spec.Task_Priority) or else
        Records.Get (Value, "acceptance") /= To_String (Spec.Acceptance) or else
        Records.Get (Value, "notes") /= Native_Notes (Spec, Predecessors)
      then
         raise Data_Error with
           "native task definition differs from the complete Improve contract for " & To_String (Spec.Id);
      end if;
   end Require_Compatible_Definition;

   function Existing_By_Origin
     (Store  : Stores.Store;
      Origin : String;
      Spec   : Improve.Model.Task_Specification;
      Kind   : String;
      Predecessors : Improve.Model.UString_Vectors.Vector) return String is
      Status : Errors.Error_Info;
      Value  : Records.Item;
   begin
      for Id of Tasks.List (Store) loop
         Tasks.Definition (Store, Id, Value, Status);
         if Errors.Is_Ok (Status) and then Records.Get (Value, "created_by") = "improve" and then
           Records.Get (Value, "origin") = Origin
         then
            Require_Compatible_Definition (Value, Spec, Kind, Origin, Predecessors);
            return Id;
         end if;
      end loop;
      return "";
   end Existing_By_Origin;

   function Publish
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
      Selected : Improve.Model.Task_Vectors.Vector;

      function Is_Selected (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
        (Selected_Task_Ids.Is_Empty or else Selected_Task_Ids.Contains (Task_Id));

      function Is_Known (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
        (for some Spec of Plan.Tasks => Spec.Id = Task_Id);

      function Contract_Of (Task_Id : Ada.Strings.Unbounded.Unbounded_String) return String is
      begin
         for Spec of Plan.Tasks loop
            if Spec.Id = Task_Id then return Improve.Model.Task_Contract_Fingerprint (Spec); end if;
         end loop;
         return "";
      end Contract_Of;

      function Is_Predecessor
        (Mapping : Improve.Storage.Publication_Record;
         Spec    : Improve.Model.Task_Specification) return Boolean is
        (Mapping.Improve_Task_Id = Spec.Id and then
         To_String (Mapping.Contract) /= Improve.Model.Task_Contract_Fingerprint (Spec) and then
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
   begin
      for Task_Id of Selected_Task_Ids loop
         if not Is_Known (Task_Id) then
            raise Data_Error with "publication selection references unknown task " & To_String (Task_Id);
         end if;
      end loop;
      for Spec of Plan.Tasks loop
         if Is_Selected (Spec.Id) then Selected.Append (Spec); end if;
      end loop;
      if Selected.Is_Empty then raise Argument_Error with "publication selection has no tasks"; end if;
      if not Stores.Is_Initialized (Project_Directory) then
         raise Dependency_Error with "model_runner project state is not initialized: " & Project_Directory;
      end if;
      if Dry_Run then
         Stores.Open_To_Read (Store, Project_Directory, Status);
      else
         Stores.Open (Store, Project_Directory, Report, Status);
      end if;
      Require_Ok (Status, "open model_runner project state");
      declare Kind : constant String := Resolve_Kind (Store, Requested_Kind); begin
         Result.Task_Kind := To_Unbounded_String (Kind);
         for Spec of Selected loop
            declare
               Contract    : constant Unbounded_String :=
                 To_Unbounded_String (Improve.Model.Task_Contract_Fingerprint (Spec));
               Origin      : Unbounded_String := To_Unbounded_String (Origin_Of (Plan, Spec));
               Harness_Id  : Unbounded_String;
               Was_Mapped  : Boolean := False;
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
                     declare Definition : Records.Item; begin
                        Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
                        Require_Ok (Status, "read previously published harness task " & To_String (Spec.Id));
                        if Mapping.Origin /= Origin then
                           raise Data_Error with "stored publication mapping has an incompatible stable origin";
                        end if;
                        Require_Compatible_Definition
                          (Definition, Spec, Kind, To_String (Mapping.Origin), Predecessors);
                     end;
                     Origin := Mapping.Origin;
                     Harness_Id := Mapping.Harness_Task_Id;
                     Was_Mapped := True;
                     exit;
                  end if;
               end loop;
               if not Was_Mapped then
                  Harness_Id := To_Unbounded_String
                    (Existing_By_Origin (Store, To_String (Origin), Spec, Kind, Predecessors));
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
         for Index in 1 .. Natural (Result.Tasks.Length) loop
            if Length (Result.Tasks (Index).Harness_Id) > 0 then
               declare
                  Spec         : constant Improve.Model.Task_Specification := Selected (Index);
                  Definition   : Records.Item;
                  Dependencies : Improve.Model.UString_Vectors.Vector;
               begin
                  for Dependency of Spec.Dependencies loop
                     declare Found : Boolean := False; begin
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
                           declare Published : constant Unbounded_String := Published_Dependency (Dependency); begin
                              if Length (Published) = 0 then
                                 raise Data_Error with
                                   "existing native task has unpublished prerequisite " & To_String (Dependency);
                              end if;
                              Dependencies.Append (Published);
                           end;
                        end if;
                     end;
                  end loop;
                  Tasks.Definition
                    (Store, To_String (Result.Tasks (Index).Harness_Id), Definition, Status);
                  Require_Ok (Status, "read complete native task definition " & To_String (Spec.Id));
                  if Records.Get (Definition, "depends_on") /= Join (Dependencies) then
                     raise Data_Error with
                       "native dependency definition differs from the Improve contract for " & To_String (Spec.Id);
                  end if;
               end;
            end if;
         end loop;
         if Existing_Only then
            Stores.Close (Store);
            return Result;
         end if;
         declare
            Change    : Stores.Transaction;
            Remaining : Natural := Natural (Selected.Length);
            Progress  : Boolean;
         begin
            if not Dry_Run then
               for Spec of Selected loop
                  for Mapping of Existing loop
                     if Is_Predecessor (Mapping, Spec) then
                        declare Target : constant String := Retirement_Target (Mapping); begin
                           if Target /= "" then
                              Tasks.Move
                                (Store, Change, To_String (Mapping.Harness_Task_Id), Target,
                                 "superseded by " & To_String (Spec.Id) & " contract " &
                                   Improve.Model.Task_Contract_Fingerprint (Spec),
                                 Status => Status, Actor => Transitions.User);
                              Require_Ok (Status, "retire superseded native task");
                           end if;
                        end;
                     end if;
                  end loop;
               end loop;
            end if;
            for Item of Result.Tasks loop
               if Length (Item.Harness_Id) > 0 then Remaining := Remaining - 1; end if;
            end loop;
            while Remaining > 0 loop
               Progress := False;
               for Index in 1 .. Natural (Selected.Length) loop
                  if Length (Result.Tasks (Index).Harness_Id) = 0 then
                     declare
                        Spec       : constant Improve.Model.Task_Specification := Selected (Index);
                        Ready      : Boolean := True;
                        Harness_Dependencies : Improve.Model.UString_Vectors.Vector;
                     begin
                        for Dependency of Spec.Dependencies loop
                           declare Found : Boolean := False; begin
                              for Other in 1 .. Natural (Result.Tasks.Length) loop
                                 if Result.Tasks (Other).Improve_Id = Dependency then
                                    Found := True;
                                    if Length (Result.Tasks (Other).Harness_Id) = 0 then Ready := False;
                                    else Harness_Dependencies.Append (Result.Tasks (Other).Harness_Id);
                                    end if;
                                    exit;
                                 end if;
                              end loop;
                              if not Found then
                                 if not Is_Known (Dependency) then
                                    raise Data_Error with "unknown persisted task dependency " & To_String (Dependency);
                                 end if;
                                 declare Published : constant Unbounded_String := Published_Dependency (Dependency);
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
                              Notes  : constant String := Native_Notes (Spec, Predecessors_Of (Spec));
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
         end;
      end;
      Stores.Close (Store);
      return Result;
   exception
      when others =>
         if Stores.Is_Open (Store) then Stores.Close (Store); end if;
         raise;
   end Publish;

   function Reconcile
     (Project_Directory : String;
      Published         : Published_Vectors.Vector) return Published_Vectors.Vector is
      Store  : Stores.Store;
      Status : Errors.Error_Info;
      Result : Published_Vectors.Vector;
   begin
      if not Stores.Is_Initialized (Project_Directory) then
         raise Dependency_Error with "model_runner project state is not initialized: " & Project_Directory;
      end if;
      Stores.Open_To_Read (Store, Project_Directory, Status);
      Require_Ok (Status, "open model_runner project state for reconciliation");
      for Value of Published loop
         declare
            Definition : Records.Item;
            Current    : Published_Task := Value;
         begin
            if Length (Value.Harness_Id) = 0 or else Length (Value.Origin) = 0 then
               raise Data_Error with "publication mapping is incomplete for " & To_String (Value.Improve_Id);
            end if;
            Tasks.Definition (Store, To_String (Value.Harness_Id), Definition, Status);
            Require_Ok (Status, "read published harness task " & To_String (Value.Harness_Id));
            if Records.Get (Definition, "created_by") /= "improve" or else
              Records.Get (Definition, "origin") /= To_String (Value.Origin)
            then
               raise Data_Error with "published harness task provenance does not match Improve mapping";
            end if;
            Current.State := To_Unbounded_String (Tasks.State_Of (Store, To_String (Value.Harness_Id)));
            Current.Recovered := True;
            Result.Append (Current);
         end;
      end loop;
      Stores.Close (Store);
      return Result;
   exception
      when others =>
         if Stores.Is_Open (Store) then Stores.Close (Store); end if;
         raise;
   end Reconcile;
end Improve.Workflow;
