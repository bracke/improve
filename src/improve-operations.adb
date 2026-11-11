with Ada.Strings.Unbounded;

package body Improve.Operations is
   use type Ada.Strings.Unbounded.Unbounded_String;
   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference) is
   begin
      if Expected.Database_Id /= Actual.Database_Id then
         raise Data_Error with "selected Ada Quality database does not own the stored plan";
      elsif Expected.Id /= Actual.Id or else Expected.Path /= Actual.Path then
         raise Data_Error with "selected Ada Quality project identity does not match the stored plan";
      end if;
   end Require_Project_Identity;

   function Storage_Read_Limits
     (Settings : Improve.Config.Settings) return Improve.Storage.Read_Limits is
      Tasks    : constant Positive := Settings.Maximum_Tasks_Per_Plan;
      Findings : constant Positive := Tasks * Settings.Maximum_Findings_Per_Task;
   begin
      return
        (Maximum_Findings     => Findings,
         Maximum_Tasks        => Tasks,
         Maximum_Task_Details => Tasks * 16,
         Maximum_Task_Links   => Findings + Tasks * 16,
         Maximum_History      => Settings.Maximum_Output_Items);
   end Storage_Read_Limits;
end Improve.Operations;
