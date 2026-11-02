with Ada_Quality.Types;
with Improve.Model;
with Improve.Source;

--  Evidence classification, identity preservation, path validation, and exact deduplication.
package Improve.Findings is
   function Normalize
     (Selected         : Improve.Source.Selection;
      Minimum_Severity : Ada_Quality.Types.Severity := Ada_Quality.Types.Low;
      Allow_Investigation : Boolean := True) return Improve.Model.Finding_Vectors.Vector;
   --  Return deterministic candidates from violations and unavailable evidence.

   function Safe_Relative_Path (Path : String) return Boolean;
   --  Test whether a diagnostic path is relative and contains no traversal component.
end Improve.Findings;

