with Ada_Quality.Reporting;
with Improve.Model;
with Improve.Source;

--  Versioned deterministic JSON serialization of read-only quality evidence.
package Improve.JSON is
   function Projects
     (Values      : Ada_Quality.Reporting.Project_Vectors.Vector;
      Snapshot_Id : String) return String;
   --  Serialize the active project registry.

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String;
   --  Serialize normalized remediation candidates.
end Improve.JSON;

