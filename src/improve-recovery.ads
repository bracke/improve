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
      Requested_Kind : String;
      Maximum         : Positive) return Recovery_Report;
   --  Resume pending publication journal entries through native harness
   --  transactions. No unjournaled draft is ever published.
   --  @param State_Path Existing Improve state database.
   --  @param Requested_Kind Configured harness task kind or auto.
   --  @param Maximum Maximum journal operations to recover.
   --  @return Recovery counts.
end Improve.Recovery;
