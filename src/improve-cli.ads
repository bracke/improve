with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;

--  Strict command-line parsing and output-stream orchestration.
package Improve.CLI is
   --  Strict parsing and execution boundary for the Improve command line.

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);
   --  Ordered command-line arguments.

   type Command_Kind is
     (Projects_Command, Findings_Command, Plan_Command, Apply_Command, Tasks_Command, Status_Command,
      Refresh_Command, Verify_Command, Recover_Command, Config_Command, Help_Command, Version_Command);
   --  Supported top-level command.
   --  @enum Projects_Command List registered projects.
   --  @enum Findings_Command List normalized findings.
   --  @enum Plan_Command Create or inspect plans.
   --  @enum Apply_Command Publish plan tasks.
   --  @enum Tasks_Command Inspect remediation tasks.
   --  @enum Status_Command Summarize remediation state.
   --  @enum Refresh_Command Reconcile and reevaluate evidence.
   --  @enum Verify_Command Evaluate completed measurement evidence.
   --  @enum Recover_Command Recover interrupted publication.
   --  @enum Config_Command Inspect or validate configuration.
   --  @enum Help_Command Display usage help.
   --  @enum Version_Command Display the application version.

   type Plan_Operation is (Create_Plan, List_Plans, Show_Plan, Approve_Plan);
   --  Plan subcommand selected by the parser.
   --  @enum Create_Plan Generate a plan.
   --  @enum List_Plans List persisted plans.
   --  @enum Show_Plan Inspect one persisted plan.
   --  @enum Approve_Plan Approve one exact immutable revision for publication.

   function Name (Command : Command_Kind) return String;
   --  Return the stable CLI command word.
   --  @param Command Command kind to render.
   --  @return Stable lowercase command word.

   type Invocation is record
      Command       : Command_Kind := Help_Command;
      Plan_Action   : Plan_Operation := Create_Plan;
      Database      : Ada.Strings.Unbounded.Unbounded_String;
      State         : Ada.Strings.Unbounded.Unbounded_String;
      Project       : Ada.Strings.Unbounded.Unbounded_String;
      Target        : Ada.Strings.Unbounded.Unbounded_String;
      Task_Id       : Ada.Strings.Unbounded.Unbounded_String;
      Status_Filter : Ada.Strings.Unbounded.Unbounded_String;
      Run_Id        : Natural := 0;
      Format        : Improve.Config.Output_Format := Improve.Config.Terminal_Format;
      Color         : Improve.Config.Color_Mode := Improve.Config.Color_Auto;
      Has_Database  : Boolean := False;
      Has_State     : Boolean := False;
      Has_Project   : Boolean := False;
      Has_Target    : Boolean := False;
      Has_Task      : Boolean := False;
      Has_Status    : Boolean := False;
      Has_Run       : Boolean := False;
      Dry_Run       : Boolean := False;
      All_Projects  : Boolean := False;
      Verbose       : Boolean := False;
      Quiet         : Boolean := False;
   end record;
   --  Fully parsed and command-validated invocation.
   --  @field Command Selected top-level command.
   --  @field Plan_Action Selected plan subcommand.
   --  @field Database Ada Quality database path.
   --  @field State Improve state database path.
   --  @field Project Project selector.
   --  @field Target Plan or positional target identity.
   --  @field Task_Id Improve task selector.
   --  @field Status_Filter Task status filter.
   --  @field Run_Id Explicit assessment identity, or zero.
   --  @field Format Selected output format.
   --  @field Color Selected color policy.
   --  @field Has_Database Whether Database was supplied explicitly.
   --  @field Has_State Whether State was supplied explicitly.
   --  @field Has_Project Whether Project was supplied.
   --  @field Has_Target Whether Target was supplied.
   --  @field Has_Task Whether Task_Id was supplied.
   --  @field Has_Status Whether Status_Filter was supplied.
   --  @field Has_Run Whether Run_Id was supplied.
   --  @field Dry_Run Whether modification is disabled.
   --  @field All_Projects Whether every project is selected.
   --  @field Verbose Whether verbose diagnostics are requested.
   --  @field Quiet Whether nonessential output is suppressed.

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

   function Run return Natural;
   --  Execute the current process command line and write each completed output atomically.
   --  @return Stable process exit code.
end Improve.CLI;

