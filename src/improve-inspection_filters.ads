with Improve.Results;

--  Deterministic presentation-only filters for read-only inspection results.
package Improve.Inspection_Filters is
   --  Presentation-only filters that never change normalized planning evidence.

   function Findings
     (Value     : Improve.Results.Finding_List;
      Indicator : String := "";
      Severity  : String := "";
      Path      : String := "") return Improve.Results.Finding_List;
   --  Filter normalized findings without changing planning evidence or identity.
   --  @param Value Complete normalized finding list.
   --  @param Indicator Optional stable indicator spelling.
   --  @param Severity Optional lowercase severity spelling.
   --  @param Path Optional path substring.
   --  @return Copy containing only matching findings.
end Improve.Inspection_Filters;
