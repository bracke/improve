with Improve.Storage;
with Ada_Quality.Reporting;

--  Native task-state reconciliation use case.
package Improve.Operations.Reconciliation is
   --  Synchronize cached harness-owned states without changing harness lifecycle state.

   procedure Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Requested_Kind   : String;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Quality_Database_Bytes : Positive := 1_073_741_824);
   --  Reconcile every stored publication mapping for one database-qualified project.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name.
   --  @param Requested_Kind Configured native remediation task kind or auto.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Maximum_Quality_Database_Bytes Maximum quality database file bytes accepted.
end Improve.Operations.Reconciliation;
