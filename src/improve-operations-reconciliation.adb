with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Source;
with Improve.Storage;
with Improve.Workflow;

package body Improve.Operations.Reconciliation is
   use Ada.Strings.Unbounded;

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String) is
      State        : Improve.Storage.Store;
      Plan         : Improve.Model.Plan_Revision;
      Publications : Improve.Storage.Publication_Vectors.Vector;
   begin
      declare Quality : Improve.Source.Repository; begin
         Improve.Source.Open (Quality, Quality_Path);
         declare Project : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Project_Selector);
         begin
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path, Writable => False);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan := Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id));
               Improve.Operations.Inspection.Require_Project_Identity (Plan.Project, Project);
               Publications := Improve.Storage.Publications (State, To_String (Plan.Plan_Id));
            end;
            Improve.Storage.Close (State);
         end;
      exception
         when others =>
            Improve.Source.Close (Quality);
            raise;
      end;
      if not Publications.Is_Empty then
         declare
            Published  : Improve.Workflow.Published_Vectors.Vector;
            Reconciled : Improve.Workflow.Published_Vectors.Vector;
            Updates    : Improve.Storage.Publication_Vectors.Vector;
         begin
            for Value of Publications loop
               Published.Append
                 (Improve.Workflow.Published_Task'
                    (Improve_Id => Value.Improve_Task_Id,
                     Harness_Id => Value.Harness_Task_Id,
                     Origin     => Value.Origin,
                     Contract   => Value.Contract,
                     State      => Value.State,
                     Recovered  => True));
            end loop;
            Reconciled := Improve.Workflow.Reconcile (To_String (Plan.Project.Path), Published);
            for Value of Reconciled loop
               Updates.Append
                 (Improve.Storage.Publication_Record'
                    (Improve_Task_Id => Value.Improve_Id,
                     Harness_Task_Id => Value.Harness_Id,
                     Origin          => Value.Origin,
                     Contract        => Value.Contract,
                     State           => Value.State,
                     Plan_Revision   => Plan.Revision));
            end loop;
            Improve.Storage.Open (State, State_Path, Writable => True);
            Improve.Storage.Update_Publication_States (State, Updates);
            Improve.Storage.Close (State);
         end;
      end if;
   end Run;
end Improve.Operations.Reconciliation;
