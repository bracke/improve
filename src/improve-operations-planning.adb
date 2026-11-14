with Ada.Containers;
with Ada.Strings.Unbounded;
with Improve.Findings;
with Improve.Planner;
with Improve.Source;

package body Improve.Operations.Planning is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   function Generate
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings;
      Dry_Run          : Boolean) return Generation_Result is
      Quality : Improve.Source.Repository;
   begin
      Improve.Source.Open
        (Quality, Quality_Path, Improve.Operations.Quality_Load_Limits (Settings),
         Settings.Maximum_Quality_Database_Bytes);
      declare
         Project  : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Project_Selector);
         Selected : constant Improve.Source.Selection :=
           Improve.Source.Select_Assessment (Quality, Project, Run_Id, Settings.Maximum_Assessment_Bytes);
         Findings : constant Improve.Model.Finding_Vectors.Vector :=
           Improve.Findings.Normalize
             (Selected,
              Improve.Config.Quality_Severity (Settings.Minimum_Severity),
              Settings.Allow_Investigation_Tasks,
              Settings.Maximum_Assessment_Findings,
              Settings.Maximum_Normalized_Finding_Bytes);
         Draft : constant Improve.Model.Plan_Revision :=
           Improve.Planner.Generate
             (Selected, Findings, Improve.Operations.Planning_Policy (Settings),
              Improve.Source.Working_Fingerprint
                (To_String (Selected.Project.Path), State_Path,
                 Settings.Maximum_Source_File_Bytes, Settings.Maximum_Source_Total_Bytes));
      begin
         if Draft.Tasks.Length > Ada.Containers.Count_Type (Settings.Maximum_Output_Items) then
            raise Data_Error with "generated plan exceeds output.maximum_output_items";
         end if;
         Improve.Source.Close (Quality);
         if Dry_Run then
            return (Plan => Draft, Existing => False);
         end if;
         declare
            State : Improve.Storage.Store;
            Saved : Improve.Storage.Save_Result;
         begin
            Improve.Storage.Open
              (State, State_Path, Writable => True,
               Limits => Improve.Operations.Storage_Read_Limits (Settings));
            Saved := Improve.Storage.Save
              (State, Draft, Improve.Operations.Storage_Read_Limits (Settings));
            Improve.Storage.Close (State);
            return (Plan => Saved.Plan, Existing => Saved.Existing);
         end;
      end;
   end Generate;

   function Load
     (State_Path : String;
      Plan_Id    : String;
      Revision   : Natural := 0;
      Limits     : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits)
      return Improve.Model.Plan_Revision is
      State : Improve.Storage.Store;
   begin
      Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
      declare
         Plan : constant Improve.Model.Plan_Revision :=
           (if Revision = 0 then Improve.Storage.Load (State, Plan_Id, Limits)
            else Improve.Storage.Load (State, Plan_Id, Positive (Revision), Limits));
      begin
         Improve.Storage.Close (State);
         return Plan;
      end;
   end Load;

   function List
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Maximum_Items    : Positive := Improve.Storage.Default_Query_Maximum;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits)
      return Improve.Storage.Summary_Vectors.Vector is
      Quality : Improve.Source.Repository;
      State   : Improve.Storage.Store;
   begin
      Improve.Source.Open (Quality, Quality_Path, Quality_Limits, Evidence_Limits.Database_Bytes);
      declare
         Project : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Project_Selector);
      begin
         Improve.Source.Close (Quality);
         Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
         declare
            Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project, Maximum_Items, Limits);
         begin
            Improve.Storage.Close (State);
            return Values;
         end;
      end;
   end List;

   function Approve
     (State_Path : String;
      Plan_Id    : String;
      Limits     : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits)
      return Improve.Model.Plan_Revision is
      State : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
   begin
      Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
      Plan := Improve.Storage.Load (State, Plan_Id, Limits);
      Improve.Storage.Approve (State, To_String (Plan.Plan_Id), Plan.Revision, Limits);
      Improve.Storage.Close (State);
      return Plan;
   end Approve;
end Improve.Operations.Planning;
