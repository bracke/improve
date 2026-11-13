package body Improve.Dependencies is
   procedure Validate (Tasks : Improve.Model.Task_Vectors.Vector) is
   begin
      Improve.Model.Validate_Task_Graph (Tasks);
   end Validate;
end Improve.Dependencies;
