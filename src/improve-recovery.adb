with Ada.Containers;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Storage;
with Improve.Workflow;
with Project_Tools.Files;

package body Improve.Recovery is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Recover
     (State_Path      : String;
      Requested_Kind : String;
      Maximum         : Positive) return Recovery_Report is
      State   : Improve.Storage.Store;
      Pending : Improve.Storage.Operation_Vectors.Vector;
      Result  : Recovery_Report;
   begin
      if not Project_Tools.Files.File_Exists (State_Path) then
         raise Dependency_Error with "Improve state database is unavailable: " & State_Path;
      end if;
      Improve.Storage.Open (State, State_Path, Writable => True);
      Pending := Improve.Storage.Pending_Publications (State);
      Improve.Storage.Close (State);
      if Pending.Length > Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "pending publication count exceeds operations.maximum_recovery_operations";
      end if;
      for Operation of Pending loop
         Improve.Storage.Open (State, State_Path, Writable => False);
         declare
            Plan : Improve.Model.Plan_Revision :=
              Improve.Storage.Load (State, To_String (Operation.Plan_Id), Operation.Revision);
            Selected : Improve.Model.Task_Vectors.Vector;
            Existing : constant Improve.Storage.Publication_Vectors.Vector :=
              Improve.Storage.Publications (State, To_String (Operation.Plan_Id));
         begin
            Improve.Storage.Close (State);
            if Length (Operation.Fingerprint) > 0 and then Plan.Fingerprint /= Operation.Fingerprint then
               raise Data_Error with "pending publication revision fingerprint does not match durable state";
            end if;
            for Spec of Plan.Tasks loop
               if Operation.Task_Ids.Contains (Spec.Id) then Selected.Append (Spec); end if;
            end loop;
            if Selected.Length /= Operation.Task_Ids.Length then
               raise Data_Error with "pending publication references tasks outside its plan";
            end if;
            Plan.Tasks := Selected;
            declare
               Published : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish
                   (To_String (Plan.Project.Path), Plan, Requested_Kind, Existing => Existing);
               Mappings  : Improve.Storage.Publication_Vectors.Vector;
            begin
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Improve_Task_Id => Value.Improve_Id,
                        Harness_Task_Id => Value.Harness_Id,
                        Origin          => Value.Origin,
                        State           => Value.State,
                        Plan_Revision   => Plan.Revision));
               end loop;
               Improve.Storage.Open (State, State_Path, Writable => True);
               Improve.Storage.Record_Publications (State, To_String (Plan.Plan_Id), Mappings);
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
