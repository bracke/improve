with Ada.Command_Line;
with Ada.Containers;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Improve.CLI.Parsing;
with Improve.CLI_Metadata;
with Improve.CLI_Audit_Output;
with Improve.CLI_Assets;
with Improve.CLI_Outputs;
with Improve.CLI_Support;
with Improve.JSON;
with Improve.Inspection_Filters;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Diagnostics;
with Improve.Operations.Publication;
with Improve.Operations.Reconciliation;
with Improve.Operations.Recovery;
with Improve.Operations.Verification;
with Improve.Presentation;
with Improve.Results;
with Improve.Text;
with Project_Tools.Files;

package body Improve.CLI is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use Improve.CLI_Support;
   use Improve.Text;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Results.Diagnostic_Status;
   LF : constant Character := Character'Val (10);
   function Name (Command : Command_Kind) return String is
     (Improve.CLI_Metadata.Command_Name (Command));

   function Parse (Arguments : String_Vectors.Vector) return Invocation is
     (Parsing.Parse (Arguments));
   function Help_Text return String is separate;

   function Configuration_Path (Item : Invocation) return String is
     (if Item.Has_Config then To_String (Item.Config)
      elsif Project_Tools.Files.File_Exists ("config/improve.toml") then "config/improve.toml"
      else "");

   function Projects_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Inspected : constant Improve.Operations.Inspection.Project_Result :=
        Improve.Operations.Inspection.Projects (Quality_Path (Item, Settings), Settings);

      function Render return String is
        (Improve.Presentation.Projects (Inspected.Values));
   begin
      if Item.Format = JSON_Format then
         return Improve.JSON.Projects (Inspected);
      end if;
      return Render_Terminal (Item, Render'Access);
   end Projects_Output;
   function Findings_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Limit : constant Positive :=
        (if Item.Has_Limit or else Item.Has_Cursor then Page_Limit (Item, Settings)
         else Settings.Maximum_Output_Items);
      Inspected : Improve.Operations.Inspection.Finding_Result :=
        Improve.Inspection_Filters.Findings
          (Improve.Operations.Inspection.Findings
             (Quality_Path (Item, Settings), To_String (Item.Project), Item.Run_Id, Settings),
           Indicator => To_String (Item.Indicator_Filter),
           Severity  => To_String (Item.Severity_Filter),
           Path      => To_String (Item.Path_Filter));

      Next : Unbounded_String;
      function Render return String is
        (Improve.Presentation.Findings (Inspected) &
         (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
   begin
      if Item.Has_Limit or else Item.Has_Cursor then
         if Item.Cursor >= Natural (Inspected.Values.Length) then
            Inspected.Values.Clear;
         elsif Item.Cursor > 0 then
            Inspected.Values.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
         end if;
         if Natural (Inspected.Values.Length) > Limit then
            Next := To_Unbounded_String (Number (Item.Cursor + Limit));
            Inspected.Values.Delete_Last (Inspected.Values.Length - Ada.Containers.Count_Type (Limit));
         end if;
      else
         Require_Output_Items
           (Inspected.Values.Length, Settings.Maximum_Output_Items, "finding output");
      end if;
      if Item.Format = JSON_Format then
         return Improve.JSON.Findings (Inspected, To_String (Next));
      end if;
      return Render_Terminal (Item, Render'Access);
   end Findings_Output;

   function Apply_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Executed : constant Improve.Operations.Publication.Result :=
        Improve.Operations.Publication.Run
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Plan_Id          => To_String (Item.Target),
           Selected_Task_Id => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Task_Kind        => To_String (Settings.Task_Kind),
           Dry_Run          => Item.Dry_Run,
           Limits           => Improve.Operations.Storage_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));

      function Render return String is
        (Improve.Presentation.Publication
           (To_String (Executed.Plan.Plan_Id), Executed.Published, Item.Dry_Run));
   begin
      Require_Output_Items
        (Executed.Published.Tasks.Length, Settings.Maximum_Output_Items, "publication output");
      if Item.Format = JSON_Format then
         return Improve.JSON.Publication
           (To_String (Executed.Plan.Plan_Id), Executed.Published, Item.Dry_Run);
      end if;
      return Render_Terminal (Item, Render'Access);
   end Apply_Output;

   function Recover_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Report : constant Improve.Operations.Recovery.Result :=
        Improve.Operations.Recovery.Run
          (State_Path (Item), Quality_Path (Item, Settings), To_String (Settings.Task_Kind),
           Settings.Maximum_Recovery_Operations, Improve.Operations.Storage_Limits (Settings),
           Improve.Operations.Quality_Load_Limits (Settings),
           Improve.Config.Evidence_Limits_Of (Settings));

      function Render return String is
        (Improve.Presentation.Recovery (Report));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Recovery (Report); end if;
      return Render_Terminal (Item, Render'Access);
   end Recover_Output;

   function Verify_Output
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Negative : out Boolean;
      Command  : String := "verify") return String is
      Executed : constant Improve.Operations.Verification.Result :=
        Improve.Operations.Verification.Run
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => To_String (Item.Project),
           Task_Id          => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Revision         => (if Item.Has_Revision then Item.Revision else 0),
           Run_Id           => Item.Run_Id,
           Settings         => Settings);

      function Render return String is
        (Improve.Presentation.Verification
           (To_String (Executed.Plan.Plan_Id), Executed.Report, Command));
   begin
      Negative := Executed.Report.Outcome /= Improve.Model.Verified;
      Require_Output_Items
        (Executed.Report.Tasks.Length, Settings.Maximum_Output_Items, "verification output");
      if Item.Format = JSON_Format then
         return Improve.JSON.Verification (Executed.Report, Command);
      end if;
      return Render_Terminal (Item, Render'Access);
   end Verify_Output;

   function Refresh_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Ignored     : Boolean;
   begin
      Improve.Operations.Reconciliation.Run
        (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
         To_String (Settings.Task_Kind),
         Improve.Operations.Storage_Limits (Settings),
         Improve.Operations.Quality_Load_Limits (Settings),
         Improve.Config.Evidence_Limits_Of (Settings));
      return Verify_Output (Item, Settings, Ignored, Command => "refresh");
   end Refresh_Output;

   function Doctor_Output
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Provider : access Improve.Refinement.Adapter'Class;
      Negative : out Boolean) return String is separate;

   function Dispatch
     (Item     : Invocation;
      Configuration : Improve.Config.Loaded_Configuration;
      Provider : access Improve.Refinement.Adapter'Class;
      Negative : out Boolean) return String is
      Settings : constant Improve.Config.Settings := Configuration.Values;
      Plain : Unbounded_String;

      function Render_Config return String is
        (Improve.Presentation.Header (Message ("config.title")) & LF & Improve.Config.Image (Settings));
   begin
      Negative := False;
      case Item.Command is
         when Help_Command => Plain := To_Unbounded_String (Help_Text);
         when Version_Command =>
            Plain := To_Unbounded_String (Message ("help.version", [Arg ("version", Version)]) & LF);
         when Config_Command =>
            if Item.Has_Target and then To_String (Item.Target) = "validate" then
               if Length (Configuration.Source_Path) = 0 then
                  raise Argument_Error with "no configuration file was selected";
               end if;
               Plain := To_Unbounded_String (Message ("config.valid") & LF);
            elsif Item.Has_Target and then To_String (Item.Target) = "explain" then
               Plain := To_Unbounded_String (Improve.Config.Explain (Configuration));
            else
               if Item.Format = JSON_Format then
                  Plain := To_Unbounded_String (Message ("config.title") & LF & Improve.Config.Image (Settings));
               else
                  return Render_Terminal (Item, Render_Config'Access);
               end if;
            end if;
         when Projects_Command => return Projects_Output (Item, Settings);
         when Findings_Command => return Findings_Output (Item, Settings);
         when Plan_Command => return Improve.CLI_Outputs.Plan_Output (Item, Settings, Provider);
         when Audit_Command => return Improve.CLI_Audit_Output.Render (Item, Settings);
         when Apply_Command => return Apply_Output (Item, Settings);
         when Tasks_Command =>
            return Improve.CLI_Outputs.Tasks_Output
              (Item, Settings, Configuration.Quality_Database_Configured);
         when Status_Command => return Improve.CLI_Outputs.Status_Output (Item, Settings);
         when Verify_Command => return Verify_Output (Item, Settings, Negative);
         when Refresh_Command => return Refresh_Output (Item, Settings);
         when Recover_Command => return Recover_Output (Item, Settings);
         when Doctor_Command => return Doctor_Output (Item, Settings, Provider, Negative);
         when Completion_Command =>
            Plain := To_Unbounded_String (Improve.CLI_Assets.Completion (To_String (Item.Target)));
         when Manpage_Command => Plain := To_Unbounded_String (Improve.CLI_Assets.Manpage);
      end case;
      if Item.Format = JSON_Format then
         return Improve.JSON.Text (Name (Item.Command), "text", To_String (Plain));
      elsif Item.Format = Markdown_Format then
         return "# Improve " & Name (Item.Command) & LF & LF & "```text" & LF & To_String (Plain) & "```" & LF;
      end if;
      return To_String (Plain);
   end Dispatch;

   type Error_Category is
     (Invalid_Input, Unavailable_Dependency, Invalid_State, Interrupted_Operation, Internal_Failure);

   function Error_Code (Category : Error_Category) return String is
     (case Category is
         when Invalid_Input => "IMP-E-ARGUMENT",
         when Unavailable_Dependency => "IMP-E-DEPENDENCY",
         when Invalid_State => "IMP-E-DATA",
         when Interrupted_Operation => "IMP-E-CANCELLED",
         when Internal_Failure => "IMP-E-INTERNAL");

   function Category_Name (Category : Error_Category) return String is
     (case Category is
         when Invalid_Input => "invalid_input",
         when Unavailable_Dependency => "unavailable_dependency",
         when Invalid_State => "invalid_state",
         when Interrupted_Operation => "cancelled",
         when Internal_Failure => "internal_failure");

   function Requests_JSON (Arguments : String_Vectors.Vector) return Boolean is
   begin
      for Index in 1 .. Natural (Arguments.Length) loop
         if Arguments (Index) = "--format=json" or else
           (Arguments (Index) = "--format" and then Index < Natural (Arguments.Length) and then
            Arguments (Index + 1) = "json")
         then
            return True;
         end if;
      end loop;
      return False;
   end Requests_JSON;

   function Diagnostic (Category : Error_Category; Detail : String) return String;

   function Error_Output
     (Category : Error_Category;
      Detail   : String;
      JSON     : Boolean;
      Hint     : String := "") return String is
   begin
      if JSON then
         return Improve.JSON.Error
           (Error_Code (Category), Category_Name (Category), Improve.Presentation.Safe_Text (Detail), Hint);
      end if;
      return Diagnostic (Category, Detail) & (if Hint = "" then "" else Hint & LF);
   end Error_Output;

   function Diagnostic (Category : Error_Category; Detail : String) return String is
      Key : constant String :=
        (case Category is
            when Invalid_Input => "error.argument",
            when Unavailable_Dependency => "error.dependency",
            when Invalid_State => "error.data",
            when Interrupted_Operation => "error.cancelled",
            when Internal_Failure => "error.internal");
      Rendered : constant String :=
        Message (Key, [Arg ("detail", Improve.Presentation.Safe_Text (Detail))]);
   begin
      return Message ("error.prefix", [Arg ("message", Rendered)]) & LF;
   end Diagnostic;

   function Configuration_For (Item : Invocation) return Improve.Config.Loaded_Configuration is
   begin
      declare
         Result : Improve.Config.Loaded_Configuration :=
           (if Item.Command in Help_Command | Version_Command | Completion_Command | Manpage_Command
            then
              (Values => Improve.Config.Defaults,
               Source_Path => Null_Unbounded_String,
               Quality_Database_Configured => False)
            else Improve.Config.Load_With_Provenance (Configuration_Path (Item)));
      begin
         if Item.No_Agent then
            Result.Values.Agent_Enabled := False;
         else
            if Item.Has_Agent_Model then Result.Values.Agent_Model := Item.Agent_Model; end if;
            if Item.Has_Agent_Model_Path then Result.Values.Agent_Model_Path := Item.Agent_Model_Path; end if;
            if Item.Has_Agent_Model_SHA256 then
               Result.Values.Agent_Model_SHA256 := Item.Agent_Model_SHA256;
            end if;
            if Item.Has_Agent_Model or else Item.Has_Agent_Model_Path or else Item.Has_Agent_Model_SHA256 then
               Result.Values.Agent_Enabled := True;
            end if;
         end if;
         Improve.Config.Validate (Result.Values);
         return Result;
      end;
   end Configuration_For;

   function Configuration_For
     (Arguments : String_Vectors.Vector) return Improve.Config.Loaded_Configuration is
     (Configuration_For (Parse (Arguments)));

   function Execute
     (Arguments : String_Vectors.Vector;
      Provider  : access Improve.Refinement.Adapter'Class) return Outcome is separate;

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
     (Execute (Arguments, Provider => null));

   procedure Write (Text : String) is
      Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
        Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Output);
   begin
      String'Write (Stream, Text);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
   end Write;

   function Run
     (Provider : access Improve.Refinement.Adapter'Class) return Natural is separate;

   function Run return Natural is (Run (Provider => null));
end Improve.CLI;

