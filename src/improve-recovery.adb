with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Operations;
with Improve.Source;
with Improve.Workflow;
with Project_Tools.Files;

package body Improve.Recovery is
   use Ada.Strings.Unbounded;

   function Number (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   function Recover
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>))
      return Recovery_Report is
      State   : Improve.Storage.Store;
      Pending : Improve.Storage.Operation_Vectors.Vector;
      Result  : Recovery_Report;

      procedure Require_Current_Authorization
        (Plan : Improve.Model.Plan_Revision) is
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path, Quality_Limits);
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Latest : constant Improve.Source.Selection :=
              Improve.Source.Select_Assessment (Quality, Project);
         begin
            Improve.Operations.Require_Project_Identity (Plan.Project, Project);
            if Latest.Baseline.Run_Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Source_Id /= Plan.Baseline.Source_Id
            then
               raise Data_Error with
                 "pending publication assessment source changed; operation retained without creating native tasks";
            elsif Latest.Baseline.Run_Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Policy_Id /= Plan.Baseline.Policy_Id
            then
               raise Data_Error with
                 "pending publication quality policy changed; operation retained without creating native tasks";
            end if;
         end;
         Improve.Source.Close (Quality);
      exception
         when others =>
            Improve.Source.Close (Quality);
            raise;
      end Require_Current_Authorization;
   begin
      if not Project_Tools.Files.File_Exists (State_Path) then
         raise Dependency_Error with "Improve state database is unavailable: " & State_Path;
      end if;
      Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
      Pending := Improve.Storage.Pending_Publications (State, Maximum, Limits);
      Improve.Storage.Close (State);
      for Operation of Pending loop
         Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Storage.Load (State, To_String (Operation.Plan_Id), Operation.Revision, Limits);
            Existing : constant Improve.Storage.Publication_Vectors.Vector :=
              Improve.Storage.Publications
                (State, To_String (Operation.Plan_Id), Limits.Maximum_History, Limits);
            Approved : constant Boolean :=
              Improve.Storage.Is_Approved
                (State, To_String (Operation.Plan_Id), Operation.Revision, Limits);
         begin
            Improve.Storage.Close (State);
            if Length (Operation.Fingerprint) > 0 and then Plan.Fingerprint /= Operation.Fingerprint then
               raise Data_Error with "pending publication revision fingerprint does not match durable state";
            end if;
            if (for some Task_Id of Operation.Task_Ids =>
                  (for all Spec of Plan.Tasks => Spec.Id /= Task_Id))
            then
               raise Data_Error with "pending publication references tasks outside its plan";
            end if;
            declare
               Kind : constant String :=
                 (if Length (Operation.Task_Kind) > 0 then To_String (Operation.Task_Kind)
                  else Requested_Kind);
               Existing_Result : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish
                   (To_String (Plan.Project.Path), Plan, Kind, Existing => Existing,
                    Selected_Task_Ids => Operation.Task_Ids, Existing_Only => True, Dry_Run => True);
               All_Existing : constant Boolean :=
                 (for all Published_Task of Existing_Result.Tasks => Published_Task.Recovered);
               Published : Improve.Workflow.Publication_Result;
               Mappings  : Improve.Storage.Publication_Vectors.Vector;
            begin
               if All_Existing then
                  Published := Existing_Result;
               else
                  if Length (Operation.Task_Kind) = 0 then
                     raise Data_Error with
                       "pending publication lacks an exact authorized task kind; operation retained";
                  elsif not Approved then
                     raise Data_Error with
                       "pending publication requires renewed approval before creating missing native tasks";
                  elsif Improve.Source.Working_Fingerprint (To_String (Plan.Project.Path), State_Path) /=
                    To_String (Plan.Working_Source_Id)
                  then
                     raise Data_Error with
                       "pending publication source is stale; operation retained without creating native tasks";
                  end if;
                  Require_Current_Authorization (Plan);
                  Published := Improve.Workflow.Publish
                    (To_String (Plan.Project.Path), Plan, Kind, Existing => Existing,
                     Selected_Task_Ids => Operation.Task_Ids);
               end if;
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Improve_Task_Id => Value.Improve_Id,
                        Harness_Task_Id => Value.Harness_Id,
                        Origin          => Value.Origin,
                        Contract        => Value.Contract,
                        State           => Value.State,
                        Plan_Revision   => Plan.Revision));
               end loop;
               Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
               Improve.Storage.Record_Publications
                 (State, To_String (Plan.Plan_Id), Mappings, Limits);
               Improve.Storage.Complete_Publication (State, Operation.Id);
               Improve.Storage.Close (State);
               Result.Operations_Recovered := Result.Operations_Recovered + 1;
               Result.Tasks_Recovered := Result.Tasks_Recovered + Natural (Published.Tasks.Length);
            end;
         end;
      end loop;
      return Result;
   exception
      when others =>
         Improve.Storage.Close (State);
         raise;
   end Recover;
end Improve.Recovery;
