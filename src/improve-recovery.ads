--  Recovery of deliberately authorized, interrupted publication operations.
package Improve.Recovery is
   type Recovery_Report is record
      Operations_Recovered : Natural := 0;
      Tasks_Recovered      : Natural := 0;
   end record;

   function Recover
     (State_Path      : String;
      Requested_Kind : String;
      Maximum         : Positive) return Recovery_Report;
   --  Resume pending publication journal entries through native harness
   --  transactions. No unjournaled draft is ever published.
end Improve.Recovery;
