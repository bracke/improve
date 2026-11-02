with Improve.Model;

--  Validation of Improve-owned task dependency graphs.
package Improve.Dependencies is
   procedure Validate (Tasks : Improve.Model.Task_Vectors.Vector);
   --  Reject duplicate task identities, missing dependency targets, self-edges,
   --  duplicate edges, and dependency cycles.
   --  @exception Data_Error The graph is invalid.
end Improve.Dependencies;
