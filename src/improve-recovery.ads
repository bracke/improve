with Ada_Quality.Reporting;
with Improve.Operations.Recovery;
with Improve.Storage;

--  Recovery of deliberately authorized, interrupted publication operations.
package Improve.Recovery is
   --  Durable recovery of explicitly authorized publication operations.

   subtype Recovery_Report is Improve.Operations.Recovery.Result;
   --  Compatibility name for the operation-layer recovery result.

   function Recover
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Quality_Database_Bytes : Positive := 1_073_741_824;
      Maximum_Assessment_Bytes : Positive := 16_777_216)
      return Recovery_Report;
   --  Resume pending publication journal entries through native harness
   --  transactions. No unjournaled draft is ever published.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Requested_Kind Configured harness task kind or auto.
   --  @param Maximum Maximum journal operations to recover.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Maximum_Quality_Database_Bytes Maximum quality database file bytes accepted.
   --  @param Maximum_Assessment_Bytes Maximum typed assessment evidence bytes accepted.
   --  @return Recovery counts.
end Improve.Recovery;
