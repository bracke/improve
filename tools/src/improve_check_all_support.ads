--  Focused validation helpers for the repository-wide check_all executable.
package Improve_Check_All_Support is
   --  Validate the workspace dependency lock and set Failed on any violation.
   procedure Validate_Dependency_Lock (Failed : in out Boolean);
end Improve_Check_All_Support;
