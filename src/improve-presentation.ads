with Ada.Finalization;
with Improve.Config;
with Ada_Quality.Reporting;
with Improve.Model;
with Improve.Operations.Recovery;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Improve.Verification;
with Improve.Workflow;
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

   function Projects (Values : Ada_Quality.Reporting.Project_Vectors.Vector) return String;
   --  Render registered projects for terminal output.
   --  @param Values Registered projects.
   --  @return Human-readable project table.

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String;
   --  Render normalized findings for terminal output.
   --  @param Selected Assessment selection.
   --  @param Values Normalized findings.
   --  @return Human-readable finding table.

   function Plan (Value : Improve.Model.Plan_Revision) return String;
   --  Render one immutable plan revision.
   --  @param Value Plan revision.
   --  @return Human-readable plan.

   function Plans (Values : Improve.Storage.Summary_Vectors.Vector) return String;
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

   function Publication
     (Plan_Id : String;
      Value   : Improve.Workflow.Publication_Result;
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

   function Recovery (Value : Improve.Operations.Recovery.Result) return String;
   --  Render publication recovery counts.
   --  @param Value Recovery report.
   --  @return Human-readable recovery result.

   function Verification
     (Plan_Id : String;
      Value   : Improve.Verification.Report;
      Command : String) return String;
   --  Render verification or refresh outcomes.
   --  @param Plan_Id Evaluated plan identity.
   --  @param Value Verification report.
   --  @param Command Command name selecting the heading.
   --  @return Human-readable verification result.
private
   type Styling_Scope is new Ada.Finalization.Limited_Controlled with record
      Previous : Terminal_Styles.Color_Policy := Terminal_Styles.Color_Auto;
   end record;

   overriding procedure Finalize (Item : in out Styling_Scope);
   --  Restore the terminal policy captured by Configure.
   --  @param Item Completed rendering scope.
end Improve.Presentation;

