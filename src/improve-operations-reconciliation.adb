with Ada.Containers.Ordered_Sets;
with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Source;
with Improve.Workflow;

package body Improve.Operations.Reconciliation is
   use Ada.Strings.Unbounded;

   package Revision_Sets is new Ada.Containers.Ordered_Sets (Positive);

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Requested_Kind   : String;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>)) is
      State : Improve.Storage.Store;

      procedure Reconcile_Plan
        (Project : Improve.Model.Project_Reference;
         Plan_Id : String) is
         Publications : Improve.Storage.Publication_Vectors.Vector;
         Updates      : Improve.Storage.Publication_Vectors.Vector;
         Revisions    : Revision_Sets.Set;

         procedure Reconcile_Revision (Revision : Positive) is
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Storage.Load (State, Plan_Id, Revision, Limits);
            Contracts : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
              Improve.Model.Effective_Task_Contracts (Plan);
            Selected      : Improve.Model.UString_Vectors.Vector;
            Mapping_Count : Natural := 0;
         begin
            Improve.Operations.Require_Project_Identity (Plan.Project, Project);
            for Mapping of Publications loop
               if Mapping.Plan_Revision = Revision then
                  Mapping_Count := Mapping_Count + 1;
               end if;
            end loop;
            for Binding of Contracts loop
               for Mapping of Publications loop
                  if Mapping.Plan_Revision = Revision and then
                    Mapping.Improve_Task_Id = Binding.Task_Id and then
                    Mapping.Contract = Binding.Fingerprint
                  then
                     Selected.Append (Binding.Task_Id);
                     exit;
                  end if;
               end loop;
            end loop;
            if Natural (Selected.Length) /= Mapping_Count then
               raise Data_Error with
                 "publication mapping does not match its originating plan revision";
            end if;
            if not Selected.Is_Empty then
               declare
                  Reconciled : constant Improve.Workflow.Publication_Result :=
                    Improve.Workflow.Publish
                      (To_String (Plan.Project.Path), Plan, Requested_Kind,
                       Existing => Publications, Selected_Task_Ids => Selected,
                       Existing_Only => True);
               begin
                  for Value of Reconciled.Tasks loop
                     Updates.Append
                       (Improve.Storage.Publication_Record'
                          (Improve_Task_Id => Value.Improve_Id,
                           Harness_Task_Id => Value.Harness_Id,
                           Origin          => Value.Origin,
                           Contract        => Value.Contract,
                           State           => Value.State,
                           Plan_Revision   => Revision));
                  end loop;
               end;
            end if;
         end Reconcile_Revision;
      begin
         Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
         Publications := Improve.Storage.Publications
           (State, Plan_Id, Limits.Maximum_History, Limits);
         for Mapping of Publications loop
            Revisions.Include (Mapping.Plan_Revision);
         end loop;
         for Revision of Revisions loop
            Reconcile_Revision (Revision);
         end loop;
         Improve.Storage.Close (State);
         if not Updates.Is_Empty then
            Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
            Improve.Storage.Update_Publication_States (State, Plan_Id, Updates, Limits);
            Improve.Storage.Close (State);
         end if;
      exception
         when others =>
            Improve.Storage.Close (State);
            raise;
      end Reconcile_Plan;
   begin
      declare Quality : Improve.Source.Repository; begin
         Improve.Source.Open (Quality, Quality_Path, Quality_Limits);
         declare Project : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Project_Selector);
         begin
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project, Limits.Maximum_History, Limits);
            begin
               if Values.Is_Empty then
                  raise Argument_Error with "project has no stored remediation plan";
               end if;
               Improve.Storage.Close (State);
               for Value of Values loop
                  Reconcile_Plan (Project, To_String (Value.Plan_Id));
               end loop;
            end;
         end;
      exception
         when others =>
            Improve.Source.Close (Quality);
            Improve.Storage.Close (State);
            raise;
      end;
   end Run;
end Improve.Operations.Reconciliation;
