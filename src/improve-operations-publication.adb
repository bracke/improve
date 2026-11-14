with Ada.Strings.Unbounded;
with Improve.Publication_Authorization;

package body Improve.Operations.Publication is
   use Ada.Strings.Unbounded;

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Plan_Id          : String;
      Selected_Task_Id : String;
      Task_Kind        : String;
      Dry_Run          : Boolean;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits) return Result
   is
      State        : Improve.Storage.Store;
      Plan         : Improve.Model.Plan_Revision;
      Existing     : Improve.Storage.Publication_Vectors.Vector;
      Selected     : Improve.Model.UString_Vectors.Vector;
      Approved     : Boolean := False;
      Operation_Id : Natural := 0;
   begin
      Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
      Plan := Improve.Storage.Load (State, Plan_Id, Limits);
      Existing := Improve.Storage.Publications
        (State, To_String (Plan.Plan_Id), Limits.Maximum_History, Limits);
      Approved := Improve.Storage.Is_Approved (State, To_String (Plan.Plan_Id), Plan.Revision, Limits);
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
      Improve.Publication_Authorization.Validate
        (Plan, State_Path, Quality_Path, Quality_Limits, Evidence_Limits);
      if not Dry_Run then
         declare
            Preflight : constant Improve.Workflow.Publication_Result :=
              Improve.Workflow.Publish
                (To_String (Plan.Project.Path), Plan, Task_Kind, Existing,
                 Selected_Task_Ids => Selected, Existing_Only => False, Dry_Run => True);
            Task_Ids : Improve.Model.UString_Vectors.Vector;
         begin
            if Selected.Is_Empty then
               for Spec of Plan.Tasks loop
                  Task_Ids.Append (Spec.Id);
               end loop;
            else
               Task_Ids := Selected;
            end if;
            Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
            Operation_Id := Improve.Storage.Begin_Publication
              (State, Plan, To_String (Preflight.Task_Kind), Task_Ids, Limits);
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
               Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
               Improve.Storage.Record_Publications
                 (State, To_String (Plan.Plan_Id), Mappings, Limits);
               Improve.Storage.Complete_Publication
                 (State, Positive (Operation_Id), Limits);
               Improve.Storage.Close (State);
            end;
         end if;
         return (Plan => Plan, Published => Published);
      end;
   end Run;
end Improve.Operations.Publication;
