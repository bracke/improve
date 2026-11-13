with Ada_Quality.Reporting;
with Improve.Storage;

--  Recovery of deliberately authorized, interrupted publication operations.
package Improve.Recovery is
   --  Durable recovery of explicitly authorized publication operations.

   type Recovery_Report is record
      Operations_Recovered : Natural := 0;
      Tasks_Recovered      : Natural := 0;
   end record;
   --  Work recovered by one bounded invocation.
   --  @field Operations_Recovered Completed journal operations.
   --  @field Tasks_Recovered Adopted or recovered task mappings.

   function Recover
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>))
      return Recovery_Report;
   --  Resume pending publication journal entries through native harness
   --  transactions. No unjournaled draft is ever published.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Requested_Kind Configured harness task kind or auto.
   --  @param Maximum Maximum journal operations to recover.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @return Recovery counts.
end Improve.Recovery;
