with Ada_Quality.Reporting;
with Improve.Model;
with Improve.Source;
with Improve.Storage;
with Improve.Workflow;
with Improve.Verification;

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

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String;
   --  Serialize a generated plan and its complete task specifications.

   function Plans (Values : Improve.Storage.Summary_Vectors.Vector) return String;
   --  Serialize persisted plan summaries.

   function Publication
     (Plan_Id : String; Value : Improve.Workflow.Publication_Result; Dry_Run : Boolean) return String;
   --  Serialize native harness publication or preview results.

   function Verification
     (Value   : Improve.Verification.Report;
      Command : String := "verify") return String;
   --  Serialize an independent quality verification report.
end Improve.JSON;

