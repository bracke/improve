with Ada_Quality.Reporting;
with Improve.Model;
with Improve.Recovery;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Improve.Workflow;
with Improve.Verification;

--  Versioned deterministic JSON serialization of read-only quality evidence.
package Improve.JSON is
   --  Versioned deterministic JSON encoders for CLI result documents.

   function Projects
     (Values      : Ada_Quality.Reporting.Project_Vectors.Vector;
      Snapshot_Id : String) return String;
   --  Serialize the active project registry.
   --  @param Values Registry projects.
   --  @param Snapshot_Id Reporting snapshot identity.
   --  @return One versioned JSON document.

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String;
   --  Serialize normalized remediation candidates.
   --  @param Selected Assessment selection and provenance.
   --  @param Values Normalized findings.
   --  @return One versioned JSON document.

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String;
   --  Serialize a generated plan and its complete task specifications.
   --  @param Value Plan revision.
   --  @param Dry_Run Whether the plan was calculated without persistence.
   --  @return One versioned JSON document.

   function Plans (Values : Improve.Storage.Summary_Vectors.Vector) return String;
   --  Serialize persisted plan summaries.
   --  @param Values Persisted plan summaries.
   --  @return One versioned JSON document.

   function Publication
     (Plan_Id : String; Value : Improve.Workflow.Publication_Result; Dry_Run : Boolean) return String;
   --  Serialize native harness publication or preview results.
   --  @param Plan_Id Stable Improve plan identity.
   --  @param Value Harness publication result.
   --  @param Dry_Run Whether publication was previewed only.
   --  @return One versioned JSON document.

   function Verification
     (Value   : Improve.Verification.Report;
      Command : String := "verify") return String;
   --  Serialize an independent quality verification report.
   --  @param Value Verification report.
   --  @param Command Command name used in the envelope.
   --  @return One versioned JSON document.

   function Tasks
     (Values : Improve.Tasks.View_Vectors.Vector;
      Filter : String) return String;
   --  Serialize deterministic task inspection results.
   --  @param Values Task views.
   --  @param Filter Applied status filter.
   --  @return One versioned JSON document.

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String;
   --  Serialize one or more project remediation summaries.
   --  @param Values Project status summaries.
   --  @return One versioned JSON document.

   function Recovery (Value : Improve.Recovery.Recovery_Report) return String;
   --  Serialize publication recovery results.
   --  @param Value Recovery report.
   --  @return One versioned JSON document.
end Improve.JSON;

