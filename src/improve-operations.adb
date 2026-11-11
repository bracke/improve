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
end Improve.Operations;
