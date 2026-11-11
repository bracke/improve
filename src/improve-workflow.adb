with Improve.Workflow_Publication;
with Model_Runner.Errors;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

package body Improve.Workflow is
   use Ada.Strings.Unbounded;

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
      if Errors.Is_Error (Status) then
         raise Data_Error with Context & ": " & Detail (Status);
      end if;
   end Require_Ok;

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
   begin
      return Improve.Workflow_Publication.Execute
        (Project_Directory, Plan, Requested_Kind, Existing,
         Selected_Task_Ids, Existing_Only, Dry_Run);
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
         if Stores.Is_Open (Store) then
            Stores.Close (Store);
         end if;
         raise;
   end Reconcile;
end Improve.Workflow;
