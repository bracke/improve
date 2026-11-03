with Ada_Quality.Types;
with Improve.Model;
with Improve.Source;

--  Evidence classification, identity preservation, path validation, and exact deduplication.
package Improve.Findings is
   --  Normalize typed assessment evidence into safe, deduplicated finding references.

   function Normalize
     (Selected         : Improve.Source.Selection;
      Minimum_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.Low;
      Allow_Investigation : Boolean := True) return Improve.Model.Finding_Vectors.Vector;
   --  Return deterministic candidates from violations and unavailable evidence.
   --  @param Selected Completed assessment and baseline provenance.
   --  @param Minimum_Severity Lowest source finding severity to retain.
   --  @param Allow_Investigation Whether unavailable evidence may create investigation candidates.
   --  @return Deterministically ordered normalized findings.

   function Safe_Relative_Path (Path : String) return Boolean;
   --  Test whether a diagnostic path is relative and contains no traversal component.
   --  @param Path Untrusted diagnostic path.
   --  @return True only for an empty or safe project-relative path.
end Improve.Findings;

