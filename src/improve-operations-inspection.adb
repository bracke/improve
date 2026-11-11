with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Improve.Source;
with Improve.Storage;

package body Improve.Operations.Inspection is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Improve.Storage.Verification_Scope;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   procedure Require_Project_Identity
     (Stored, Current : Improve.Model.Project_Reference) is
   begin
      if Stored.Database_Id /= Current.Database_Id then
         raise Data_Error with "selected Ada Quality database does not own the stored plan";
      elsif Stored.Id /= Current.Id or else Stored.Path /= Current.Path then
         raise Data_Error with "selected Ada Quality project identity does not match the stored plan";
      end if;
   end Require_Project_Identity;

   function Views_For
     (State              : in out Improve.Storage.Store;
      Plan               : Improve.Model.Plan_Revision;
      Current_Assessment : Natural;
      Maximum_Items      : Positive) return Improve.Tasks.View_Vectors.Vector is
   begin
      if Plan.Tasks.Length > Ada.Containers.Count_Type (Maximum_Items) then
         raise Data_Error with "task query exceeds output.maximum_output_items";
      end if;
      declare
         Publications : constant Improve.Storage.Publication_Vectors.Vector :=
           Improve.Storage.Publications (State, To_String (Plan.Plan_Id), Maximum_Items);
         Verifications : constant Improve.Storage.Verification_Vectors.Vector :=
           Improve.Storage.Verifications
             (State, To_String (Plan.Plan_Id), Maximum => Maximum_Items);
      begin
         return Improve.Tasks.Build
           (Plan, Publications, Verifications, Current_Assessment, Maximum_Items);
      end;
   end Views_For;

   function Tasks
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Filter           : String;
      Maximum_Items    : Positive) return Improve.Tasks.View_Vectors.Vector is
      State              : Improve.Storage.Store;
      Selected_Project   : Improve.Model.Project_Reference :=
        (Id => 1, Name | Path | Database_Id => Null_Unbounded_String);
      Has_Project        : constant Boolean := Project_Selector /= "";
      Current_Assessment : Natural := 0;
      Result             : Improve.Tasks.View_Vectors.Vector;
      Found_Task         : Boolean := Task_Id = "";
   begin
      if not Improve.Tasks.Valid_Filter (Filter) then
         raise Argument_Error with "invalid task status filter: " & Filter;
      end if;
      if Has_Project then
         declare Quality : Improve.Source.Repository; begin
            Improve.Source.Open (Quality, Quality_Path);
            Selected_Project := Improve.Source.Resolve_Project (Quality, Project_Selector);
            Current_Assessment :=
              Improve.Source.Select_Assessment (Quality, Selected_Project).Baseline.Run_Id;
            Improve.Source.Close (Quality);
         exception
            when others =>
               Improve.Source.Close (Quality);
               raise;
         end;
      end if;
      Improve.Storage.Open (State, State_Path, Writable => False);
      if Task_Id /= "" then
         declare
            Plan : constant Improve.Model.Plan_Revision := Improve.Storage.Load_Task (State, Task_Id, Revision);
            Views : constant Improve.Tasks.View_Vectors.Vector :=
              Views_For (State, Plan, Current_Assessment, Maximum_Items);
         begin
            if Has_Project then
               begin
                  Require_Project_Identity (Plan.Project, Selected_Project);
               exception
                  when Data_Error => raise Argument_Error with "task does not belong to selected project";
               end;
            end if;
            for View of Views loop
               if To_String (View.Improve_Id) = Task_Id then
                  Found_Task := True;
                  if Improve.Tasks.Matches (View, Filter) then
                     if Result.Length >= Ada.Containers.Count_Type (Maximum_Items) then
                        raise Data_Error with "task query exceeds output.maximum_output_items";
                     end if;
                     Result.Append (View);
                  end if;
               end if;
            end loop;
         end;
      else
         declare Summaries : constant Improve.Storage.Summary_Vectors.Vector :=
           (if Has_Project then Improve.Storage.List (State, Selected_Project) else Improve.Storage.List (State));
         begin
            if Summaries.Length > Ada.Containers.Count_Type (Maximum_Items) then
               raise Data_Error with "task query exceeds output.maximum_output_items";
            end if;
            for Summary of Summaries loop
               declare
                  Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Storage.Load (State, To_String (Summary.Plan_Id));
                  Remaining : constant Natural := Maximum_Items - Natural (Result.Length);
                  Views : constant Improve.Tasks.View_Vectors.Vector :=
                    (if Remaining = 0 and then not Plan.Tasks.Is_Empty
                     then raise Data_Error with "task query exceeds output.maximum_output_items"
                     else Views_For (State, Plan, Current_Assessment, Positive'Max (1, Remaining)));
               begin
                  for View of Views loop
                     if Improve.Tasks.Matches (View, Filter) then
                        if Result.Length >= Ada.Containers.Count_Type (Maximum_Items) then
                           raise Data_Error with "task query exceeds output.maximum_output_items";
                        end if;
                        Result.Append (View);
                     end if;
                  end loop;
               end;
            end loop;
         end;
      end if;
      Improve.Storage.Close (State);
      if not Found_Task then raise Argument_Error with "unknown Improve task " & Task_Id; end if;
      Improve.Tasks.Sort (Result);
      return Result;
   end Tasks;

   function Status
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      All_Projects     : Boolean;
      Maximum_Items    : Positive) return Improve.Tasks.Status_Vectors.Vector is
      State       : Improve.Storage.Store;
      Quality     : Improve.Source.Repository;
      Result      : Improve.Tasks.Status_Vectors.Vector;
      Total_Items : Natural := 0;

      procedure Add_Project (Project : Improve.Model.Project_Reference; Latest_Run : Natural) is
         Summaries : constant Improve.Storage.Summary_Vectors.Vector := Improve.Storage.List (State, Project);
         Value     : Improve.Tasks.Project_Status;
         Last_Plan : Improve.Model.Plan_Revision;
         Last_Views : Improve.Tasks.View_Vectors.Vector;
         Has_Plan  : Boolean := False;
      begin
         Value.Project_Id := Project.Id;
         Value.Project := Project.Name;
         Value.Latest_Run := Latest_Run;
         Value.Plan_Count := Natural (Summaries.Length);
         for Summary of Summaries loop
            declare
               Plan : constant Improve.Model.Plan_Revision :=
                 Improve.Storage.Load (State, To_String (Summary.Plan_Id));
               Remaining : constant Natural := Maximum_Items - Total_Items;
               Views : constant Improve.Tasks.View_Vectors.Vector :=
                 (if Remaining = 0 and then not Plan.Tasks.Is_Empty
                  then raise Data_Error with "status query exceeds output.maximum_output_items"
                  else Views_For (State, Plan, Latest_Run, Positive'Max (1, Remaining)));
               Latest_Project_Run : Natural := 0;
               Latest_Plan_Run : Natural := 0;
            begin
               for Evidence of Improve.Storage.Verifications (State, To_String (Plan.Plan_Id)) loop
                  if Evidence.Plan_Revision = Plan.Revision and then
                    Evidence.Contract_Fingerprint = Plan.Fingerprint and then
                    Evidence.Scope = Improve.Storage.Project_Evaluation and then
                    Evidence.Assessment_Id >= Latest_Project_Run
                  then
                     Latest_Project_Run := Evidence.Assessment_Id;
                     Value.Project_Quality := Evidence.Outcome;
                     Value.Has_Project_Verification := True;
                     Value.Project_Verification_Run := Evidence.Assessment_Id;
                  elsif Evidence.Plan_Revision = Plan.Revision and then
                    Evidence.Contract_Fingerprint = Plan.Fingerprint and then
                    Evidence.Scope = Improve.Storage.Plan_Evaluation and then
                    Evidence.Assessment_Id >= Latest_Plan_Run
                  then
                     Latest_Plan_Run := Evidence.Assessment_Id;
                     Value.Plan_Quality := Evidence.Outcome;
                     Value.Has_Plan_Verification := True;
                     Value.Plan_Verification_Run := Evidence.Assessment_Id;
                  end if;
               end loop;
               if Natural (Views.Length) > Maximum_Items - Total_Items then
                  raise Data_Error with "status query exceeds output.maximum_output_items";
               end if;
               Value.Tasks.Append_Vector (Views);
               Last_Plan := Plan;
               Last_Views := Views;
               Value.Baseline_Run := Plan.Baseline.Run_Id;
               Has_Plan := True;
               Total_Items := Total_Items + Natural (Views.Length);
            end;
         end loop;
         if Has_Plan then Value.Findings := Improve.Tasks.Findings (Last_Plan, Last_Views); end if;
         Improve.Tasks.Sort (Value.Tasks);
         if Result.Length >= Ada.Containers.Count_Type (Maximum_Items) then
            raise Data_Error with "status query exceeds output.maximum_output_items";
         end if;
         Result.Append (Value);
      end Add_Project;

      procedure Add_Resolved_Project (Project : Improve.Model.Project_Reference) is
         Latest : Natural := 0;
      begin
         begin
            Latest := Improve.Source.Select_Assessment (Quality, Project).Baseline.Run_Id;
         exception
            when Dependency_Error => null;
         end;
         Add_Project (Project, Latest);
      end Add_Resolved_Project;
   begin
      Improve.Source.Open (Quality, Quality_Path);
      Improve.Storage.Open (State, State_Path, Writable => False);
      if All_Projects then
         declare Projects : constant Ada_Quality.Reporting.Project_Vectors.Vector := Improve.Source.Projects (Quality);
         begin
            if Projects.Length > Ada.Containers.Count_Type (Maximum_Items) then
               raise Data_Error with "status query exceeds output.maximum_output_items";
            end if;
            for Registered of Projects loop
               Add_Resolved_Project (Improve.Source.Resolve_Project (Quality, Number (Registered.Id)));
            end loop;
         end;
      else
         Add_Resolved_Project (Improve.Source.Resolve_Project (Quality, Project_Selector));
      end if;
      Improve.Storage.Close (State);
      Improve.Source.Close (Quality);
      return Result;
   exception
      when others =>
         Improve.Storage.Close (State);
         Improve.Source.Close (Quality);
         raise;
   end Status;
end Improve.Operations.Inspection;
