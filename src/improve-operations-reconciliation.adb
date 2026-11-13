with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Source;
with Improve.Workflow;

package body Improve.Operations.Reconciliation is
   use Ada.Strings.Unbounded;

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Requested_Kind   : String;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>)) is
      State        : Improve.Storage.Store;
      Plan         : Improve.Model.Plan_Revision;
      Publications : Improve.Storage.Publication_Vectors.Vector;
   begin
      declare Quality : Improve.Source.Repository; begin
         Improve.Source.Open (Quality, Quality_Path, Quality_Limits);
         declare Project : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Project_Selector);
         begin
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path, Writable => False);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project, Limits.Maximum_History);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan := Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id), Limits);
               Improve.Operations.Require_Project_Identity (Plan.Project, Project);
               Publications := Improve.Storage.Publications
                 (State, To_String (Plan.Plan_Id), Limits.Maximum_History, Limits);
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
            Contracts : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
              Improve.Model.Effective_Task_Contracts (Plan);
            Selected  : Improve.Model.UString_Vectors.Vector;
         begin
            for Binding of Contracts loop
               for Mapping of Publications loop
                  if Mapping.Improve_Task_Id = Binding.Task_Id and then
                    Mapping.Contract = Binding.Fingerprint
                  then
                     Selected.Append (Binding.Task_Id);
                     exit;
                  end if;
               end loop;
            end loop;
            if not Selected.Is_Empty then
               declare
                  Reconciled : constant Improve.Workflow.Publication_Result :=
                    Improve.Workflow.Publish
                      (To_String (Plan.Project.Path), Plan, Requested_Kind, Existing => Publications,
                       Selected_Task_Ids => Selected, Existing_Only => True);
                  Updates : Improve.Storage.Publication_Vectors.Vector;
               begin
                  for Value of Reconciled.Tasks loop
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
                  Improve.Storage.Update_Publication_States (State, To_String (Plan.Plan_Id), Updates);
                  Improve.Storage.Close (State);
               end;
            end if;
         end;
      end if;
   end Run;
end Improve.Operations.Reconciliation;
