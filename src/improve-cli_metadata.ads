with Improve.CLI;

--  Single source of stable command-line command and option metadata.
private package Improve.CLI_Metadata is
   type Option_Kind is
     (Config_Option, Database_Option, State_Option, Project_Option, Format_Option, Color_Option,
      Progress_Option, Run_Option, Revision_Option, Against_Revision_Option, Task_Option, Status_Option,
      Indicator_Option, Severity_Option, Path_Option, Limit_Option, Cursor_Option, Signing_Key_Option,
      Verification_Key_Option, Agent_Model_Option, Agent_Model_Path_Option, Agent_Model_SHA256_Option,
      No_Agent_Option, Dry_Run_Option, Release_Option, All_Option, Verbose_Option, Quiet_Option,
      Help_Option, Version_Option);

   type Operation_Context is
     (No_Operation, Plan_Create_Operation, Plan_List_Operation, Plan_Show_Operation,
      Plan_Approve_Operation, Plan_Diff_Operation, Plan_Explain_Operation, Plan_Graph_Operation,
      Audit_Export_Operation, Audit_Verify_Operation);

   function Command_Name (Command : Improve.CLI.Command_Kind) return String;
   function Parse_Command (Text : String; Command : out Improve.CLI.Command_Kind) return Boolean;
   function Command_Words return String;
   function Command_List return String;
   function Command_Help_Key (Command : Improve.CLI.Command_Kind) return String;
   function Positional_Values (Command : Improve.CLI.Command_Kind) return String;
   function Positional_Value_Allowed (Command : Improve.CLI.Command_Kind; Text : String) return Boolean;

   function Word (Option : Option_Kind) return String;
   function Parse_Option (Text : String; Option : out Option_Kind) return Boolean;
   function Takes_Value (Option : Option_Kind) return Boolean;
   function File_Value (Option : Option_Kind) return Boolean;
   function Completion_Values (Option : Option_Kind) return String;
   function Completion_Description (Option : Option_Kind) return String;
   function Help_Display (Option : Option_Kind) return String;
   function Help_Key (Option : Option_Kind) return String;
   function Document_In_Help (Option : Option_Kind) return Boolean;
   function Accepted_By_Command
     (Option  : Option_Kind;
      Command : Improve.CLI.Command_Kind) return Boolean;
   function Accepted_In_Context
     (Option  : Option_Kind;
      Command : Improve.CLI.Command_Kind;
      Context : Operation_Context) return Boolean;
   function Context_For
     (Command      : Improve.CLI.Command_Kind;
      Plan_Action  : Improve.CLI.Plan_Operation;
      Audit_Verify : Boolean) return Operation_Context;
   function Context_Command (Context : Operation_Context) return Improve.CLI.Command_Kind;
   function Context_Name (Context : Operation_Context) return String;
   function Parse_Progress_Mode (Text : String; Value : out Improve.CLI.Progress_Mode) return Boolean;
   function Plan_Operation_Name (Value : Improve.CLI.Plan_Operation) return String;
   function Parse_Plan_Operation (Text : String; Value : out Improve.CLI.Plan_Operation) return Boolean;
   function Value_Expectation (Option : Option_Kind) return String;

   function Plan_Operation_Words return String;
end Improve.CLI_Metadata;
