with Improve.Model;
with Improve.Results;

--  Deterministic comparison and explanation of immutable plan revisions.
package Improve.Plan_Diffs is
   --  Stable revision comparison independent of storage and presentation.

   function Compare
     (Earlier : Improve.Model.Plan_Revision;
      Later   : Improve.Model.Plan_Revision) return Improve.Results.Plan_Comparison;
   --  Compare complete plan provenance, evidence, and task contracts.
   --  @param Earlier Earlier immutable revision.
   --  @param Later Later immutable revision of the same plan.
   --  @return Stable ordered difference explanation.

   function Explain
     (Current  : Improve.Model.Plan_Revision;
      Previous : Improve.Model.Plan_Revision) return Improve.Results.Plan_Comparison;
   --  Explain why Current differs from Previous, or describe an initial revision.
   --  @param Current Revision being explained.
   --  @param Previous Preceding revision, or Current for an initial revision.
   --  @return Stable ordered explanation.
end Improve.Plan_Diffs;
