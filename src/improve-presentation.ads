with Ada.Finalization;
with Improve.Config;
with Improve.Model;
with Improve.Results;
with Improve.State;
with Improve.Tasks;
with Terminal_Styles;

--  Terminal styling policy kept separate from command data.
package Improve.Presentation is
   --  Shared terminal styling boundary for human-readable output.

   type Styling_Scope is limited private;
   --  Scoped terminal styling policy restored automatically after rendering.

   function Configure
     (Format : Improve.Config.Output_Format;
      Color  : Improve.Config.Color_Mode) return Styling_Scope;
   --  Apply output styling policy for the lifetime of the returned scope.
   --  @param Format Selected output format.
   --  @param Color Requested terminal color policy.
   --  @return Scope that restores the preceding terminal policy when finalized.

   function Header (Text : String) return String;
   --  Decorate a terminal heading according to the current policy.
   --  @param Text Heading text.
   --  @return Styled or plain heading.

   function Safe_Text (Text : String) return String;
   --  Replace terminal control characters in untrusted text with spaces.
   --  @param Text Untrusted diagnostic, path, title, or evidence text.
   --  @return Single-line terminal-safe text.

   function Projects (Values : Improve.Results.Project_Vectors.Vector) return String;
   --  Render registered projects for terminal output.
   --  @param Values Registered projects.
   --  @return Human-readable project table.

   function Findings (Value : Improve.Results.Finding_List) return String;
   --  Render normalized findings for terminal output.
   --  @param Value Assessment provenance and normalized findings.
   --  @return Human-readable finding table.

   function Plan (Value : Improve.Model.Plan_Revision) return String;
   --  Render one immutable plan revision.
   --  @param Value Plan revision.
   --  @return Human-readable plan.

   function Plans (Values : Improve.State.Summary_Vectors.Vector) return String;
   --  Render plan summaries.
   --  @param Values Plan summaries.
   --  @return Human-readable plan list.

   function Generated_Plan
     (Value    : Improve.Model.Plan_Revision;
      Dry_Run  : Boolean;
      Existing : Boolean) return String;
   --  Render a planning result.
   --  @param Value Generated or reused plan.
   --  @param Dry_Run Whether persistence was skipped.
   --  @param Existing Whether an identical revision already existed.
   --  @return Human-readable planning result.

   function Plan_Approval (Value : Improve.Model.Plan_Revision) return String;
   --  Render a successful exact-revision approval.
   --  @param Value Approved plan revision.
   --  @return Human-readable approval result.

   function Plan_Comparison (Value : Improve.Results.Plan_Comparison; Explain : Boolean) return String;
   --  Render a plan revision comparison or explanation.
   --  @param Value Deterministic revision comparison.
   --  @param Explain Whether the output explains one revision rather than presenting a raw diff.
   --  @return Human-readable comparison.

   function Diagnostics (Value : Improve.Results.Diagnostic_Report) return String;
   --  Render read-only diagnostic checks.
   --  @param Value Diagnostic report.
   --  @return Human-readable diagnostics.

   function Audit (Value : Improve.Results.Audit_Bundle) return String;
   --  Render a concise audit-bundle summary.
   --  @param Value Exact plan, approval, publication, and verification evidence.
   --  @return Human-readable audit summary.

   function Publication
     (Plan_Id : String;
      Value   : Improve.Results.Publication_Result;
      Dry_Run : Boolean) return String;
   --  Render native task publication mappings.
   --  @param Plan_Id Published plan identity.
   --  @param Value Publication result.
   --  @param Dry_Run Whether publication was only validated.
   --  @return Human-readable publication result.

   function Tasks (Values : Improve.Tasks.View_Vectors.Vector) return String;
   --  Render operational task views.
   --  @param Values Task views.
   --  @return Human-readable task table.

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String;
   --  Render project remediation status.
   --  @param Values Project status records.
   --  @return Human-readable status report.

   function Recovery (Value : Improve.Results.Recovery_Result) return String;
   --  Render publication recovery counts.
   --  @param Value Recovery report.
   --  @return Human-readable recovery result.

   function Verification
     (Plan_Id : String;
      Value   : Improve.Results.Verification_Report;
      Command : String) return String;
   --  Render verification or refresh outcomes.
   --  @param Plan_Id Evaluated plan identity.
   --  @param Value Verification report.
   --  @param Command Command name selecting the heading.
   --  @return Human-readable verification result.
private
   function Waiting_Styling_Tasks return Natural;
   --  Return the number of tasks queued for the presentation styling lock.
   --  @return Number of queued tasks.

   type Styling_Scope is new Ada.Finalization.Limited_Controlled with record
      Previous : Terminal_Styles.Color_Policy := Terminal_Styles.Color_Auto;
      Acquired : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Styling_Scope);
   --  Restore the terminal policy captured by Configure.
   --  @param Item Completed rendering scope.
end Improve.Presentation;

