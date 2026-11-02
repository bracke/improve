with Ada.Containers;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

package body Improve.Workflow is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   package Errors renames Model_Runner.Errors;
   package Records renames Model_Runner.Framework.Records;
   package Stores renames Model_Runner.Framework.Stores;
   package Tasks renames Model_Runner.Framework.Tasks;

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

   function Origin_Of (Plan : Improve.Model.Plan_Revision; Improve_Id : String) return String is
     ("improve:" & To_String (Plan.Fingerprint) & ":" & Improve_Id);

   function Harness_Priority (Value : Improve.Model.Priority) return String is
     (case Value is
         when Improve.Model.Critical_Priority => "100",
         when Improve.Model.High_Priority => "75",
         when Improve.Model.Normal_Priority => "50",
         when Improve.Model.Low_Priority => "25");

   function Existing_By_Origin (Store : Stores.Store; Origin : String) return String is
      Status : Errors.Error_Info;
      Value  : Records.Item;
   begin
      for Id of Tasks.List (Store) loop
         Tasks.Definition (Store, Id, Value, Status);
         if Errors.Is_Ok (Status) and then Records.Get (Value, "created_by") = "improve" and then
           Records.Get (Value, "origin") = Origin
         then
            return Id;
         end if;
      end loop;
      return "";
   end Existing_By_Origin;

   function Join (Values : Improve.Model.UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         if Length (Result) > 0 then Append (Result, ", "); end if;
         Append (Result, Value);
      end loop;
      return To_String (Result);
   end Join;

   function Publish
     (Project_Directory : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Dry_Run           : Boolean := False) return Publication_Result is
      Store  : Stores.Store;
      Report : Stores.Recovery_Report;
      Status : Errors.Error_Info;
      Result : Publication_Result;
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
      declare Kind : constant String := Resolve_Kind (Store, Requested_Kind); begin
         Result.Task_Kind := To_Unbounded_String (Kind);
         for Spec of Plan.Tasks loop
            declare
               Origin   : constant String := Origin_Of (Plan, To_String (Spec.Id));
               Existing : constant String := Existing_By_Origin (Store, Origin);
            begin
               Result.Tasks.Append
                 (Published_Task'
                    (Improve_Id => Spec.Id,
                     Harness_Id => To_Unbounded_String (Existing),
                     Origin     => To_Unbounded_String (Origin),
                     State      => To_Unbounded_String
                       (if Existing = "" then (if Dry_Run then "candidate" else "")
                        else Tasks.State_Of (Store, Existing)),
                     Recovered  => Existing /= ""));
            end;
         end loop;
         declare
            Change    : Stores.Transaction;
            Remaining : Natural := Natural (Plan.Tasks.Length);
            Progress  : Boolean;
         begin
            for Item of Result.Tasks loop
               if Length (Item.Harness_Id) > 0 then Remaining := Remaining - 1; end if;
            end loop;
            while Remaining > 0 loop
               Progress := False;
               for Index in 1 .. Natural (Plan.Tasks.Length) loop
                  if Length (Result.Tasks (Index).Harness_Id) = 0 then
                     declare
                        Spec       : constant Improve.Model.Task_Specification := Plan.Tasks (Index);
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
                              if not Found then raise Data_Error with "unknown persisted task dependency"; end if;
                           end;
                        end loop;
                        if Ready then
                           declare
                              Fields : Tasks.Field_Map;
                              Id     : Unbounded_String;
                              Notes  : constant String :=
                                "Improve task " & To_String (Spec.Id) & ASCII.LF &
                                "Goal: " & To_String (Spec.Goal) & ASCII.LF &
                                "Evidence:" & ASCII.LF & To_String (Spec.Evidence) & ASCII.LF &
                                "Scope: " & To_String (Spec.Scope) & ASCII.LF &
                                "Out of scope: " & To_String (Spec.Out_Of_Scope) & ASCII.LF &
                                "Verification: " & To_String (Spec.Verification);
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
end Improve.Workflow;
