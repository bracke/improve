with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Publication_Authorization;
with Improve.State;
with Improve.Workflow;
with Project_Tools.Files;

package body Improve.Operations.Recovery is
   use Ada.Strings.Unbounded;

   function Run
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits) return Result is
      State   : Improve.Storage.Store;
      Pending : Improve.State.Publication_Operation_Vectors.Vector;
      Value   : Result;
      Namespace : constant String := Improve.Operations.Publication_Namespace
        (State_Path, Limits, Initialize => True);
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
            Existing : constant Improve.State.Publication_Vectors.Vector :=
              Improve.Storage.Publications
                (State, To_String (Operation.Plan_Id), Limits.Maximum_History, Limits);
            Approved : constant Boolean :=
              Improve.Storage.Is_Approved
                (State, To_String (Operation.Plan_Id), Operation.Revision, Limits);
         begin
            Improve.Storage.Close (State);
            if Length (Operation.Fingerprint) > 0 and then Plan.Fingerprint /= Operation.Fingerprint then
               raise Data_Error with "pending publication revision fingerprint does not match durable state";
            elsif Length (Operation.Content_Fingerprint) = 0 or else
              Improve.Model.Plan_Content_Fingerprint (Plan) /= To_String (Operation.Content_Fingerprint)
            then
               raise Data_Error with "pending publication plan content does not match durable state";
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
                   (To_String (Plan.Project.Path), Namespace,
                    Plan, Kind, Existing => Existing,
                    Selected_Task_Ids => Operation.Task_Ids, Existing_Only => True, Dry_Run => True);
               All_Existing : constant Boolean :=
                 (for all Published_Task of Existing_Result.Tasks => Published_Task.Recovered);
               Published : Improve.Workflow.Publication_Result;
               Mappings  : Improve.State.Publication_Vectors.Vector;
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
                  end if;
                  Improve.Publication_Authorization.Validate
                    (Plan, State_Path, Quality_Path, Quality_Limits,
                     Evidence_Limits,
                     Retain_On_Failure => True);
                  Published := Improve.Workflow.Publish
                    (To_String (Plan.Project.Path), Namespace,
                     Plan, Kind, Existing => Existing,
                     Selected_Task_Ids => Operation.Task_Ids);
               end if;
               for Published_Task of Published.Tasks loop
                  Mappings.Append
                    (Improve.State.Publication_Record'
                       (Improve_Task_Id => Published_Task.Improve_Id,
                        Harness_Task_Id => Published_Task.Harness_Id,
                        Origin          => Published_Task.Origin,
                        Contract        => Published_Task.Contract,
                        State           => Published_Task.State,
                        Plan_Revision   => Plan.Revision));
               end loop;
               Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
               Improve.Storage.Record_Publications
                 (State, To_String (Plan.Plan_Id), Mappings, Limits);
               Improve.Storage.Complete_Publication (State, Operation.Id, Limits);
               Improve.Storage.Close (State);
               Value.Operations_Recovered := Value.Operations_Recovered + 1;
               Value.Tasks_Recovered := Value.Tasks_Recovered + Natural (Published.Tasks.Length);
            end;
         end;
      end loop;
      return Value;
   end Run;
end Improve.Operations.Recovery;
