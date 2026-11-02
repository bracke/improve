with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;

--  Strict command-line parsing and output-stream orchestration.
package Improve.CLI is
   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => String);

   type Command_Kind is
     (Projects_Command, Findings_Command, Plan_Command, Apply_Command, Tasks_Command, Status_Command,
      Refresh_Command, Verify_Command, Recover_Command, Config_Command, Help_Command, Version_Command);
   type Plan_Operation is (Create_Plan, List_Plans, Show_Plan);

   function Name (Command : Command_Kind) return String;
   --  Return the stable CLI command word.

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

   function Parse (Arguments : String_Vectors.Vector) return Invocation;
   --  Parse a complete command line without writing output.
   --  @exception Argument_Error Any unknown, repeated, missing, malformed, or command-incompatible argument.

   Success_Exit      : constant := 0;
   Negative_Exit     : constant := 1;
   Argument_Exit     : constant := 2;
   Unavailable_Exit  : constant := 3;
   Failure_Exit      : constant := 4;

   type Outcome is record
      Exit_Code : Natural := Success_Exit;
      Output    : Ada.Strings.Unbounded.Unbounded_String;
      Errors    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Execute (Arguments : String_Vectors.Vector) return Outcome;
   --  Execute in process and return complete stdout/stderr documents.

   function Run return Natural;
   --  Execute the current process command line and write each completed output atomically.
end Improve.CLI;

