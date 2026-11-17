with Ada.Directories;
with Ada.Strings.Unbounded;

package body Improve.Operations is
   use type Ada.Strings.Unbounded.Unbounded_String;

   function Publication_Namespace
     (State_Path : String;
      Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Initialize : Boolean := False) return String is
      State : Improve.Storage.Store;
   begin
      if State_Path = "" then
         raise Argument_Error with "Improve state path must not be empty";
      elsif not Ada.Directories.Exists (State_Path) then
         raise Dependency_Error with "Improve state database not found: " & State_Path;
      end if;
      Improve.Storage.Open (State, State_Path, Writable => Initialize, Limits => Limits);
      declare Store_Id : constant String := Improve.Storage.Identity (State); begin
         Improve.Storage.Close (State);
         return
           (if Store_Id /= "" then "store:" & Store_Id
            else "legacy-preview:" & Ada.Directories.Full_Name (State_Path));
      end;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         raise Argument_Error with "Improve state path is invalid: " & State_Path;
   end Publication_Namespace;

   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference) is
   begin
      if Expected.Database_Id /= Actual.Database_Id then
         raise Data_Error with "selected Ada Quality database does not own the stored plan";
      elsif Expected.Id /= Actual.Id or else Expected.Path /= Actual.Path then
         raise Data_Error with "selected Ada Quality project identity does not match the stored plan";
      end if;
   end Require_Project_Identity;

   function Storage_Limits
     (Settings : Improve.Config.Settings) return Improve.Storage.Persistence_Limits is
      Tasks    : constant Positive := Settings.Maximum_Tasks_Per_Plan;
      Findings : constant Positive := Tasks * Settings.Maximum_Findings_Per_Task;
   begin
      return
        (Maximum_Findings          => Findings,
         Maximum_Tasks             => Tasks,
         Maximum_Task_Details      => Tasks * 16,
         Maximum_Task_Associations => Findings + Tasks * 16,
         Maximum_History           => Settings.Maximum_History_Items,
         Maximum_Migration_Rows    => Settings.Maximum_Migration_Rows,
         Maximum_Text_Bytes        => Settings.Maximum_Persisted_Text_Bytes,
         Maximum_Total_Bytes       => Settings.Maximum_Persisted_Total_Bytes);
   end Storage_Limits;

   function Quality_Load_Limits
     (Settings : Improve.Config.Settings) return Ada_Quality.Reporting.Load_Limits is
     ((Max_Projects => Settings.Maximum_Quality_Projects,
       Max_Runs     => Settings.Maximum_Quality_Runs,
       Max_Findings => Settings.Maximum_Quality_Findings,
       others       => <>));

   function Planning_Policy
     (Settings : Improve.Config.Settings) return Improve.Planner.Policy is
     ((Minimum_Severity           => Improve.Config.Quality_Severity (Settings.Minimum_Severity),
       Maximum_Tasks              => Settings.Maximum_Tasks_Per_Plan,
       Maximum_Findings_Per_Task  => Settings.Maximum_Findings_Per_Task,
       Allow_Investigation        => Settings.Allow_Investigation_Tasks,
       Require_Review             => Settings.Require_Review,
       Maximum_Source_File_Bytes  => Settings.Maximum_Source_File_Bytes,
       Maximum_Source_Total_Bytes => Settings.Maximum_Source_Total_Bytes));

   function Verification_Policy
     (Settings : Improve.Config.Settings) return Improve.Verification.Policy is
     ((Maximum_Assessment_Findings      => Settings.Maximum_Assessment_Findings,
       Maximum_Normalized_Finding_Bytes => Settings.Maximum_Normalized_Finding_Bytes,
       Require_Fresh_Measurement        => Settings.Require_Fresh_Measurement,
       Require_Same_Policy              => Settings.Require_Same_Policy,
       Require_Same_Toolchain           => Settings.Require_Same_Toolchain,
       Require_No_New_Critical_Findings => Settings.Require_No_New_Critical));

   function Refinement_Limits
     (Settings : Improve.Config.Settings) return Improve.Refinement.Limits is
     ((Maximum_Context_Bytes     => Settings.Agent_Max_Context_Bytes,
       Maximum_File_Bytes        => Settings.Agent_Max_File_Bytes,
       Maximum_Response_Bytes    => Settings.Agent_Max_Response_Bytes,
       Timeout_Seconds           => Settings.Agent_Timeout_Seconds,
       Maximum_Findings_Per_Task => Settings.Maximum_Findings_Per_Task,
       Maximum_Tasks             => Settings.Maximum_Tasks_Per_Plan));
end Improve.Operations;
