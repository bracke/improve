with Improve.Storage;

--  Native task-state reconciliation use case.
package Improve.Operations.Reconciliation is
   --  Synchronize cached harness-owned states without changing harness lifecycle state.

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits);
   --  Reconcile the latest plan for one database-qualified project.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name.
   --  @param Limits Hard persistence and history limits.
end Improve.Operations.Reconciliation;
