with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Refinement;

--  Strict command-line parsing and output-stream orchestration.
package Improve.CLI is
   --  Strict parsing and execution boundary for the Improve command line.

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   --  Ordered command-line arguments.

   type Command_Kind is
     (Projects_Command, Findings_Command, Plan_Command, Audit_Command, Apply_Command, Tasks_Command, Status_Command,
      Refresh_Command, Verify_Command, Recover_Command, Doctor_Command, Config_Command, Completion_Command,
      Manpage_Command, Help_Command, Version_Command);
   --  Supported top-level command.
   --  @enum Projects_Command List registered projects.
   --  @enum Findings_Command List normalized findings.
   --  @enum Plan_Command Create or inspect plans.
   --  @enum Audit_Command Export immutable plan evidence and lifecycle history.
   --  @enum Apply_Command Publish plan tasks.
   --  @enum Tasks_Command Inspect remediation tasks.
   --  @enum Status_Command Summarize remediation state.
   --  @enum Refresh_Command Reconcile and reevaluate evidence.
   --  @enum Verify_Command Evaluate completed measurement evidence.
   --  @enum Recover_Command Recover interrupted publication.
   --  @enum Doctor_Command Diagnose local configuration and state read-only.
   --  @enum Config_Command Inspect or validate configuration.
   --  @enum Completion_Command Generate shell completion source.
   --  @enum Manpage_Command Generate the Improve manual page.
   --  @enum Help_Command Display usage help.
   --  @enum Version_Command Display the application version.

   type Plan_Operation is
     (Create_Plan, List_Plans, Show_Plan, Approve_Plan, Diff_Plan, Explain_Plan, Graph_Plan);
   --  Plan subcommand selected by the parser.
   --  @enum Create_Plan Generate a plan.
   --  @enum List_Plans List persisted plans.
   --  @enum Show_Plan Inspect one persisted plan.
   --  @enum Approve_Plan Approve one exact immutable revision for publication.
   --  @enum Diff_Plan Compare two exact immutable revisions.
   --  @enum Explain_Plan Explain one revision relative to its predecessor.
   --  @enum Graph_Plan Render one revision's dependency graph.

   type Progress_Mode is (Progress_Auto, Progress_Always, Progress_Never);
   --  Runtime progress display policy.
   --  @enum Progress_Auto Show progress only when standard error is a terminal.
   --  @enum Progress_Always Show progress even when standard error is redirected.
   --  @enum Progress_Never Suppress runtime progress.

   function Name (Command : Command_Kind) return String;
   --  Return the stable CLI command word.
   --  @param Command Command kind to render.
   --  @return Stable lowercase command word.

   type Invocation is record
      Command       : Command_Kind := Help_Command;
      Plan_Action   : Plan_Operation := Create_Plan;
      Config        : Ada.Strings.Unbounded.Unbounded_String;
      Database      : Ada.Strings.Unbounded.Unbounded_String;
      State         : Ada.Strings.Unbounded.Unbounded_String;
      Project       : Ada.Strings.Unbounded.Unbounded_String;
      Target        : Ada.Strings.Unbounded.Unbounded_String;
      Task_Id       : Ada.Strings.Unbounded.Unbounded_String;
      Status_Filter : Ada.Strings.Unbounded.Unbounded_String;
      Indicator_Filter : Ada.Strings.Unbounded.Unbounded_String;
      Severity_Filter  : Ada.Strings.Unbounded.Unbounded_String;
      Path_Filter      : Ada.Strings.Unbounded.Unbounded_String;
      Signing_Key      : Ada.Strings.Unbounded.Unbounded_String;
      Agent_Model      : Ada.Strings.Unbounded.Unbounded_String;
      Agent_Model_Path : Ada.Strings.Unbounded.Unbounded_String;
      Agent_Model_SHA256 : Ada.Strings.Unbounded.Unbounded_String;
      Run_Id        : Natural := 0;
      Revision      : Natural := 0;
      Against_Revision : Natural := 0;
      Limit         : Natural := 0;
      Cursor        : Natural := 0;
      Format        : Improve.Config.Output_Format := Improve.Config.Terminal_Format;
      Color         : Improve.Config.Color_Mode := Improve.Config.Color_Auto;
      Progress      : Progress_Mode := Progress_Auto;
      Has_Database  : Boolean := False;
      Has_Config    : Boolean := False;
      Has_State     : Boolean := False;
      Has_Project   : Boolean := False;
      Has_Target    : Boolean := False;
      Has_Task      : Boolean := False;
      Has_Status    : Boolean := False;
      Has_Indicator : Boolean := False;
      Has_Severity  : Boolean := False;
      Has_Path      : Boolean := False;
      Has_Signing_Key : Boolean := False;
      Has_Agent_Model : Boolean := False;
      Has_Agent_Model_Path : Boolean := False;
      Has_Agent_Model_SHA256 : Boolean := False;
      Has_Run       : Boolean := False;
      Has_Revision  : Boolean := False;
      Has_Against_Revision : Boolean := False;
      Has_Limit     : Boolean := False;
      Has_Cursor    : Boolean := False;
      Audit_Verify  : Boolean := False;
      Release_Check : Boolean := False;
      Has_Format    : Boolean := False;
      Has_Color     : Boolean := False;
      Has_Progress  : Boolean := False;
      Dry_Run       : Boolean := False;
      All_Projects  : Boolean := False;
      Verbose       : Boolean := False;
      Quiet         : Boolean := False;
      No_Agent      : Boolean := False;
   end record;
   --  Fully parsed and command-validated invocation.
   --  @field Command Selected top-level command.
   --  @field Plan_Action Selected plan subcommand.
   --  @field Config Explicit Improve configuration path.
   --  @field Database Ada Quality database path.
   --  @field State Improve state database path.
   --  @field Project Project selector.
   --  @field Target Plan or positional target identity.
   --  @field Task_Id Improve task selector.
   --  @field Status_Filter Task status filter.
   --  @field Indicator_Filter Finding indicator filter.
   --  @field Severity_Filter Finding severity filter.
   --  @field Path_Filter Finding path filter.
   --  @field Signing_Key Optional Ed25519 seed file for audit export.
   --  @field Agent_Model Invocation-local model identity override.
   --  @field Agent_Model_Path Invocation-local model path override.
   --  @field Agent_Model_SHA256 Invocation-local expected model digest override.
   --  @field Run_Id Explicit assessment identity, or zero.
   --  @field Revision Explicit immutable plan revision, or zero.
   --  @field Against_Revision Earlier revision used by plan diff, or zero.
   --  @field Limit Requested page size, or zero for the configured maximum.
   --  @field Cursor Stable result offset for a paged inspection.
   --  @field Format Selected output format.
   --  @field Color Selected color policy.
   --  @field Progress Runtime progress display policy.
   --  @field Has_Database Whether Database was supplied explicitly.
   --  @field Has_Config Whether Config was supplied explicitly.
   --  @field Has_State Whether State was supplied explicitly.
   --  @field Has_Project Whether Project was supplied.
   --  @field Has_Target Whether Target was supplied.
   --  @field Has_Task Whether Task_Id was supplied.
   --  @field Has_Status Whether Status_Filter was supplied.
   --  @field Has_Indicator Whether Indicator_Filter was supplied.
   --  @field Has_Severity Whether Severity_Filter was supplied.
   --  @field Has_Path Whether Path_Filter was supplied.
   --  @field Has_Signing_Key Whether Signing_Key was supplied.
   --  @field Has_Agent_Model Whether Agent_Model was supplied.
   --  @field Has_Agent_Model_Path Whether Agent_Model_Path was supplied.
   --  @field Has_Agent_Model_SHA256 Whether Agent_Model_SHA256 was supplied.
   --  @field Has_Run Whether Run_Id was supplied.
   --  @field Has_Revision Whether Revision was supplied.
   --  @field Has_Against_Revision Whether Against_Revision was supplied.
   --  @field Has_Limit Whether Limit was supplied.
   --  @field Has_Cursor Whether Cursor was supplied.
   --  @field Audit_Verify Whether audit verifies an exported document.
   --  @field Release_Check Whether doctor resolves the release manifest.
   --  @field Has_Format Whether Format was supplied explicitly.
   --  @field Has_Color Whether Color was supplied explicitly.
   --  @field Has_Progress Whether Progress was supplied explicitly.
   --  @field Dry_Run Whether modification is disabled.
   --  @field All_Projects Whether every project is selected.
   --  @field Verbose Whether verbose diagnostics are requested.
   --  @field Quiet Whether nonessential output is suppressed.
   --  @field No_Agent Whether refinement is disabled for this invocation.

   function Parse (Arguments : String_Vectors.Vector) return Invocation;
   --  Parse a complete command line without writing output.
   --  @param Arguments Ordered command-line arguments excluding the executable name.
   --  @return Validated invocation.
   --  @exception Argument_Error Any unknown, repeated, missing, malformed, or command-incompatible argument.

   Success_Exit      : constant := 0;
   --  Successful operation.
   Negative_Exit     : constant := 1;
   --  Successful evaluation with an unresolved result.
   Argument_Exit     : constant := 2;
   --  Invalid command or configuration.
   Unavailable_Exit  : constant := 3;
   --  Required evidence or project state is unavailable.
   Failure_Exit      : constant := 4;
   --  Storage, integrity, publication, or internal failure.
   Interrupted_Exit  : constant := 130;
   --  Operation interrupted by cooperative user cancellation.

   type Outcome is record
      Exit_Code : Natural := Success_Exit;
      Output    : Ada.Strings.Unbounded.Unbounded_String;
      Errors    : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Complete in-process command result.
   --  @field Exit_Code Stable process exit code.
   --  @field Output Complete stdout document.
   --  @field Errors Complete stderr diagnostics.

   function Execute (Arguments : String_Vectors.Vector) return Outcome;
   --  Execute in process and return complete stdout/stderr documents.
   --  @param Arguments Ordered command-line arguments excluding the executable name.
   --  @return Atomic command outcome.

   function Configuration_For
     (Arguments : String_Vectors.Vector) return Improve.Config.Loaded_Configuration;
   --  Resolve the same configuration that Execute will use.
   --  @param Arguments Ordered command-line arguments excluding the executable name.
   --  @return Parsed configuration and its provenance.

   function Execute
     (Arguments : String_Vectors.Vector;
      Provider  : access Improve.Refinement.Adapter'Class) return Outcome;
   --  Execute with an optional refinement provider for plan creation.
   --  @param Arguments Ordered command-line arguments excluding the executable name.
   --  @param Provider Runtime provider, or null when unavailable.
   --  @return Atomic command outcome.

   function Run return Natural;
   --  Execute the current process command line and write each completed output atomically.
   --  @return Stable process exit code.

   function Run
     (Provider : access Improve.Refinement.Adapter'Class) return Natural;
   --  Execute the current process command line with an optional refinement provider.
   --  @param Provider Runtime provider, or null when unavailable.
   --  @return Stable process exit code.
end Improve.CLI;

