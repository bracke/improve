with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Source;
with Improve.Storage;

package body Improve.Operations.Publication is
   use Ada.Strings.Unbounded;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference) is
   begin
      if Expected.Database_Id /= Actual.Database_Id then
         raise Data_Error with "selected Ada Quality database does not own the stored plan";
      elsif Expected.Id /= Actual.Id or else Expected.Path /= Actual.Path then
         raise Data_Error with "selected Ada Quality project identity does not match the stored plan";
      end if;
   end Require_Project_Identity;

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Plan_Id          : String;
      Selected_Task_Id : String;
      Task_Kind        : String;
      Dry_Run          : Boolean) return Result
   is
      State        : Improve.Storage.Store;
      Plan         : Improve.Model.Plan_Revision;
      Existing     : Improve.Storage.Publication_Vectors.Vector;
      Selected     : Improve.Model.UString_Vectors.Vector;
      Approved     : Boolean := False;
      Operation_Id : Natural := 0;
   begin
      Improve.Storage.Open (State, State_Path, Writable => False);
      Plan := Improve.Storage.Load (State, Plan_Id);
      Existing := Improve.Storage.Publications (State, To_String (Plan.Plan_Id));
      Approved := Improve.Storage.Is_Approved (State, To_String (Plan.Plan_Id), Plan.Revision);
      Improve.Storage.Close (State);
      if Selected_Task_Id /= "" then
         if (for all Spec of Plan.Tasks => To_String (Spec.Id) /= Selected_Task_Id) then
            raise Argument_Error with "task does not belong to plan: " & Selected_Task_Id;
         end if;
         Selected.Append (To_Unbounded_String (Selected_Task_Id));
      end if;
      if not Dry_Run and then
        (To_String (Plan.Review_Status) = "pending" or else
         (for some Spec of Plan.Tasks => Spec.Requires_Review)) and then not Approved
      then
         raise Argument_Error with
           "plan revision requires approval; run improve plan approve " & To_String (Plan.Plan_Id);
      end if;
      if Improve.Source.Working_Fingerprint (To_String (Plan.Project.Path), State_Path) /=
        To_String (Plan.Working_Source_Id)
      then
         raise Data_Error with
           "current project source differs from the assessment baseline; remeasure and refresh the plan";
      end if;
      declare
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path);
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Latest : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
         begin
            Require_Project_Identity (Plan.Project, Project);
            if Latest.Assessment.Run.Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Source_Id /= Plan.Baseline.Source_Id
            then
               raise Data_Error with "project source changed after planning; refresh the plan before publication";
            elsif Latest.Assessment.Run.Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Policy_Id /= Plan.Baseline.Policy_Id
            then
               raise Data_Error with
                 "quality policy changed after planning; replan before publication to preserve acceptance intent";
            end if;
         end;
         Improve.Source.Close (Quality);
      end;
      if not Dry_Run then
         declare
            Preflight : constant Improve.Workflow.Publication_Result :=
              Improve.Workflow.Publish
                (To_String (Plan.Project.Path), Plan, Task_Kind, Existing,
                 Selected_Task_Ids => Selected, Existing_Only => False, Dry_Run => True);
            pragma Unreferenced (Preflight);
            Task_Ids : Improve.Model.UString_Vectors.Vector;
         begin
            if Selected.Is_Empty then
               for Spec of Plan.Tasks loop
                  Task_Ids.Append (Spec.Id);
               end loop;
            else
               Task_Ids := Selected;
            end if;
            Improve.Storage.Open (State, State_Path, Writable => True);
            Operation_Id := Improve.Storage.Begin_Publication (State, Plan, Task_Ids);
            Improve.Storage.Close (State);
         end;
      end if;
      declare
         Published : constant Improve.Workflow.Publication_Result :=
           Improve.Workflow.Publish
             (To_String (Plan.Project.Path), Plan, Task_Kind, Existing, Selected, False, Dry_Run);
      begin
         if not Dry_Run then
            declare Mappings : Improve.Storage.Publication_Vectors.Vector; begin
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.Contract, Value.State, Plan.Revision));
               end loop;
               Improve.Storage.Open (State, State_Path, Writable => True);
               Improve.Storage.Record_Publications (State, To_String (Plan.Plan_Id), Mappings);
               Improve.Storage.Complete_Publication (State, Positive (Operation_Id));
               Improve.Storage.Close (State);
            end;
         end if;
         return (Plan => Plan, Published => Published);
      end;
   end Run;
end Improve.Operations.Publication;
