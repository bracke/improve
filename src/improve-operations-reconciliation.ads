with Improve.Storage;
with Improve.Config;
with Ada_Quality.Reporting;

--  Native task-state reconciliation use case.
package Improve.Operations.Reconciliation is
   --  Synchronize cached harness-owned states without changing harness lifecycle state.

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Requested_Kind   : String;
      Limits           : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits);
   --  Reconcile every stored publication mapping for one database-qualified project.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name.
   --  @param Requested_Kind Configured native remediation task kind or auto.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
end Improve.Operations.Reconciliation;
