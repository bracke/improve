with Improve.Model;

--  Validation of Improve-owned task dependency graphs.
package Improve.Dependencies is
   --  Deterministic validation of task identities and dependency DAGs.

   procedure Validate (Tasks : Improve.Model.Task_Vectors.Vector);
   --  Reject duplicate task identities, missing dependency targets, self-edges,
   --  duplicate edges, and dependency cycles.
   --  @param Tasks Complete task set whose dependency graph is validated.
   --  @exception Data_Error The graph is invalid.
end Improve.Dependencies;
