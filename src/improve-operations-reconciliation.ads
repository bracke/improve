--  Native task-state reconciliation use case.
package Improve.Operations.Reconciliation is
   --  Synchronize cached harness-owned states without changing harness lifecycle state.

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String);
   --  Reconcile the latest plan for one database-qualified project.
end Improve.Operations.Reconciliation;
