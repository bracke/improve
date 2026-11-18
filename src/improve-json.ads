with Improve.Model;
with Improve.Results;
with Improve.State;
with Improve.Tasks;

--  Versioned deterministic JSON serialization of read-only quality evidence.
package Improve.JSON is
   --  Versioned deterministic JSON encoders for CLI result documents.

   function Text (Command, Kind, Value : String) return String;
   --  Serialize a generic textual command result.
   --  @param Command Stable command name.
   --  @param Kind Stable result kind.
   --  @param Value Rendered text value.
   --  @return One versioned JSON document.

   function Projects (Value : Improve.Results.Project_List) return String;
   --  Serialize the active project registry.
   --  @param Value Registry projects and reporting snapshot identity.
   --  @return One versioned JSON document.

   function Findings (Value : Improve.Results.Finding_List; Next_Cursor : String := "") return String;
   --  Serialize normalized remediation candidates.
   --  @param Value Assessment selection, provenance, and normalized findings.
   --  @param Next_Cursor Cursor for a following finding page, or empty.
   --  @return One versioned JSON document.

   function Plan (Value : Improve.Model.Plan_Revision; Dry_Run : Boolean) return String;
   --  Serialize a generated plan and its complete task specifications.
   --  @param Value Plan revision.
   --  @param Dry_Run Whether the plan was calculated without persistence.
   --  @return One versioned JSON document.

   function Plan_Graph (Value : Improve.Model.Plan_Revision) return String;
   --  Serialize task nodes and dependency edges for one plan revision.
   --  @param Value Plan revision.
   --  @return One versioned JSON graph document.

   function Plans (Values : Improve.State.Summary_Vectors.Vector; Next_Cursor : String := "") return String;
   --  Serialize persisted plan summaries.
   --  @param Values Persisted plan summaries.
   --  @param Next_Cursor Cursor for a following plan page, or empty.
   --  @return One versioned JSON document.

   function Plan_Approval (Value : Improve.Model.Plan_Revision) return String;
   --  Serialize durable approval of one exact immutable plan revision.
   --  @param Value Approved plan revision.
   --  @return One versioned JSON document.

   function Plan_Comparison (Value : Improve.Results.Plan_Comparison; Explain : Boolean) return String;
   --  Serialize a deterministic plan revision comparison.
   --  @param Value Revision comparison.
   --  @param Explain Whether this is an explanation request.
   --  @return One versioned JSON document.

   function Diagnostics (Value : Improve.Results.Diagnostic_Report) return String;
   --  Serialize read-only diagnostic checks.
   --  @param Value Diagnostic report.
   --  @return One versioned JSON document.

   function Audit
     (Value        : Improve.Results.Audit_Bundle;
      Next_Cursor  : String := "";
      Signing_Seed : String := "") return String;
   --  Serialize one deterministic plan audit bundle.
   --  @param Value Exact plan, approval, publication, and verification evidence.
   --  @param Next_Cursor Cursor for a following history page, or empty.
   --  @param Signing_Seed Optional Ed25519 private seed in hexadecimal.
   --  @return One versioned JSON document.

   function Error
     (Code, Category, Detail : String;
      Hint                   : String := "") return String;
   --  Serialize one stable machine-readable command failure.
   --  @param Code Stable error identifier.
   --  @param Category Stable error category.
   --  @param Detail Safe diagnostic detail.
   --  @param Hint Optional corrective hint.
   --  @return One versioned JSON error document.

   function Publication
     (Plan_Id : String; Value : Improve.Results.Publication_Result; Dry_Run : Boolean) return String;
   --  Serialize native harness publication or preview results.
   --  @param Plan_Id Stable Improve plan identity.
   --  @param Value Harness publication result.
   --  @param Dry_Run Whether publication was previewed only.
   --  @return One versioned JSON document.

   function Verification
     (Value   : Improve.Results.Verification_Report;
      Command : String := "verify") return String;
   --  Serialize an independent quality verification report.
   --  @param Value Verification report.
   --  @param Command Command name used in the envelope.
   --  @return One versioned JSON document.

   function Tasks
     (Values : Improve.Tasks.View_Vectors.Vector;
      Filter : String;
      Next_Cursor : String := "") return String;
   --  Serialize deterministic task inspection results.
   --  @param Values Task views.
   --  @param Filter Applied status filter.
   --  @param Next_Cursor Cursor for a following task page, or empty.
   --  @return One versioned JSON document.

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String;
   --  Serialize one or more project remediation summaries.
   --  @param Values Project status summaries.
   --  @return One versioned JSON document.

   function Recovery (Value : Improve.Results.Recovery_Result) return String;
   --  Serialize publication recovery results.
   --  @param Value Recovery report.
   --  @return One versioned JSON document.
end Improve.JSON;

