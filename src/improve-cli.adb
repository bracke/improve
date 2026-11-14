with Ada.Command_Line;
with Ada.Containers;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Improve.CLI.Parsing;
with Improve.JSON;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Planning;
with Improve.Operations.Publication;
with Improve.Operations.Reconciliation;
with Improve.Operations.Recovery;
with Improve.Operations.Verification;
with Improve.Presentation;
with Improve.Storage;
with Improve.Tasks;
with Improve.Text;
with Jsonlib.Documents;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Improve.CLI is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use Improve.Text;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Quality_Outcome;

   LF : constant Character := Character'Val (10);

   procedure Require_Output_Items
     (Count : Ada.Containers.Count_Type;
      Limit : Positive;
      Name  : String) is
   begin
      if Count > Ada.Containers.Count_Type (Limit) then
         raise Data_Error with Name & " exceeds output.maximum_output_items";
      end if;
   end Require_Output_Items;

   function Name (Command : Command_Kind) return String is
     (case Command is
         when Projects_Command => "projects", when Findings_Command => "findings", when Plan_Command => "plan",
         when Apply_Command => "apply", when Tasks_Command => "tasks", when Status_Command => "status",
         when Refresh_Command => "refresh", when Verify_Command => "verify", when Recover_Command => "recover",
         when Config_Command => "config", when Help_Command => "help", when Version_Command => "version");

   function Parse (Arguments : String_Vectors.Vector) return Invocation is
     (Parsing.Parse (Arguments));

   function Help_Text return String is
      Result : Unbounded_String;
      procedure Line (Left, Key : String; Width : Positive := 28) is
      begin
         Append (Result, "  " & Left & [1 .. Integer'Max (1, Width - Left'Length) => ' '] & Message (Key) & LF);
      end Line;
   begin
      Append (Result, Message ("help.usage") & LF & LF & Message ("help.commands") & LF);
      Line ("projects", "help.cmd.projects"); Line ("findings", "help.cmd.findings");
      Line ("plan", "help.cmd.plan"); Line ("apply", "help.cmd.apply"); Line ("tasks", "help.cmd.tasks");
      Line ("status", "help.cmd.status"); Line ("refresh", "help.cmd.refresh");
      Line ("verify", "help.cmd.verify"); Line ("recover", "help.cmd.recover");
      Line ("config", "help.cmd.config"); Line ("help", "help.cmd.help"); Line ("version", "help.cmd.version");
      Append (Result, LF & Message ("help.options") & LF);
      Line ("--config PATH", "help.opt.config", 36);
      Line ("--database PATH", "help.opt.database", 36); Line ("--state PATH", "help.opt.state", 36);
      Line ("--project ID|NAME", "help.opt.project", 36);
      Line ("--format terminal|json", "help.opt.format", 36);
      Line ("--color auto|always|never", "help.opt.color", 36);
      Line ("--run ID", "help.opt.run", 36); Line ("--revision NUMBER", "help.opt.revision", 36);
      Line ("--task ID", "help.opt.task", 36);
      Line ("--status STATUS", "help.opt.status", 36); Line ("--dry-run", "help.opt.dry_run", 36);
      Line ("--all", "help.opt.all", 36);
      Line ("--verbose", "help.opt.verbose", 36); Line ("--quiet", "help.opt.quiet", 36);
      Line ("--help", "help.opt.help", 36);
      Append (Result, LF & Message ("help.exit") & LF);
      return To_String (Result);
   end Help_Text;

   function JSON_Output (Command, Kind, Text : String) return String is
      Doc  : Jsonlib.Documents.Document;
      Root : constant Jsonlib.Documents.Node := Doc.New_Object;
      Data : constant Jsonlib.Documents.Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String (Command));
      Doc.Insert (Data, "kind", Doc.New_String (Kind));
      Doc.Insert (Data, "text", Doc.New_String (Text));
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end JSON_Output;

   function Configuration_Path (Item : Invocation) return String is
     (if Item.Has_Config then To_String (Item.Config)
      elsif Project_Tools.Files.File_Exists ("config/improve.toml") then "config/improve.toml"
      else "");

   function Quality_Path (Item : Invocation; Settings : Improve.Config.Settings) return String is
     (if Item.Has_Database then To_String (Item.Database) else To_String (Settings.Quality_Database));

   function State_Path (Item : Invocation) return String is
     (if Item.Has_State then To_String (Item.State) else ".improve.db");

   function Projects_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Inspected : constant Improve.Operations.Inspection.Project_Result :=
        Improve.Operations.Inspection.Projects (Quality_Path (Item, Settings), Settings);
   begin
      if Item.Format = JSON_Format then
         return Improve.JSON.Projects (Inspected.Values, To_String (Inspected.Snapshot));
      end if;
      return Improve.Presentation.Projects (Inspected.Values);
   end Projects_Output;

   function Findings_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Inspected : constant Improve.Operations.Inspection.Finding_Result :=
        Improve.Operations.Inspection.Findings
          (Quality_Path (Item, Settings), To_String (Item.Project), Item.Run_Id, Settings);
   begin
      if Item.Format = JSON_Format then
         return Improve.JSON.Findings (Inspected.Selected, Inspected.Values);
      end if;
      return Improve.Presentation.Findings (Inspected.Selected, Inspected.Values);
   end Findings_Output;

   function Plan_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
   begin
      if Item.Plan_Action = Approve_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Approve
                (State_Path (Item), To_String (Item.Target),
                 Improve.Operations.Storage_Read_Limits (Settings));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Approval (Plan); end if;
            return Improve.Presentation.Plan_Approval (Plan);
         end;
      elsif Item.Plan_Action = Show_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Load
                (State_Path (Item), To_String (Item.Target),
                 (if Item.Has_Revision then Item.Revision else 0),
                 Improve.Operations.Storage_Read_Limits (Settings));
         begin
            Require_Output_Items (Plan.Tasks.Length, Settings.Maximum_Output_Items, "plan task output");
            if Item.Format = JSON_Format then return Improve.JSON.Plan (Plan, Dry_Run => False); end if;
            return Improve.Presentation.Plan (Plan);
         end;
      elsif Item.Plan_Action = List_Plans then
         declare
            Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Operations.Planning.List
                (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
                 Settings.Maximum_Output_Items, Improve.Operations.Storage_Read_Limits (Settings),
                 Improve.Operations.Quality_Load_Limits (Settings),
                 Improve.Config.Evidence_Limits_Of (Settings));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plans (Values); end if;
            return Improve.Presentation.Plans (Values);
         end;
      end if;
      declare
         Executed : constant Improve.Operations.Planning.Generation_Result :=
           Improve.Operations.Planning.Generate
             (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
              Item.Run_Id, Settings, Item.Dry_Run);
         Plan   : constant Improve.Model.Plan_Revision := Executed.Plan;
      begin
         return
           (if Item.Format = JSON_Format then Improve.JSON.Plan (Plan, Item.Dry_Run)
            else Improve.Presentation.Generated_Plan (Plan, Item.Dry_Run, Executed.Existing));
      end;
   end Plan_Output;

   function Apply_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Executed : constant Improve.Operations.Publication.Result :=
        Improve.Operations.Publication.Run
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Plan_Id          => To_String (Item.Target),
           Selected_Task_Id => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Task_Kind        => To_String (Settings.Task_Kind),
           Dry_Run          => Item.Dry_Run,
           Limits           => Improve.Operations.Storage_Read_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));
   begin
      Require_Output_Items
        (Executed.Published.Tasks.Length, Settings.Maximum_Output_Items, "publication output");
      if Item.Format = JSON_Format then
         return Improve.JSON.Publication
           (To_String (Executed.Plan.Plan_Id), Executed.Published, Item.Dry_Run);
      end if;
      return
        Improve.Presentation.Publication
          (To_String (Executed.Plan.Plan_Id), Executed.Published, Item.Dry_Run);
   end Apply_Output;

   function Tasks_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Filter     : constant String := (if Item.Has_Status then To_String (Item.Status_Filter) else "all");
      Filtered   : constant Improve.Tasks.View_Vectors.Vector :=
        Improve.Operations.Inspection.Tasks
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.Has_Project then To_String (Item.Project) else ""),
           Task_Id          => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Revision         => Item.Revision,
           Filter           => Filter,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Require_Quality  =>
             Item.Has_Database or else
             Length (Settings.Source_Path) > 0 or else
             To_String (Settings.Quality_Database) /= To_String (Improve.Config.Defaults.Quality_Database),
           Limits           => Improve.Operations.Storage_Read_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Tasks (Filtered, Filter); end if;
      return Improve.Presentation.Tasks (Filtered);
   end Tasks_Output;

   function Status_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Values : constant Improve.Tasks.Status_Vectors.Vector :=
        Improve.Operations.Inspection.Status
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.All_Projects then "" else To_String (Item.Project)),
           All_Projects     => Item.All_Projects,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Limits           => Improve.Operations.Storage_Read_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Status (Values); end if;
      return Improve.Presentation.Status (Values);
   end Status_Output;

   function Recover_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Report : constant Improve.Operations.Recovery.Result :=
        Improve.Operations.Recovery.Run
          (State_Path (Item), Quality_Path (Item, Settings), To_String (Settings.Task_Kind),
           Settings.Maximum_Recovery_Operations, Improve.Operations.Storage_Read_Limits (Settings),
           Improve.Operations.Quality_Load_Limits (Settings),
           Improve.Config.Evidence_Limits_Of (Settings));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Recovery (Report); end if;
      return Improve.Presentation.Recovery (Report);
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
   begin
      Negative := Executed.Report.Outcome /= Improve.Model.Verified;
      Require_Output_Items
        (Executed.Report.Tasks.Length, Settings.Maximum_Output_Items, "verification output");
      if Item.Format = JSON_Format then
         return Improve.JSON.Verification (Executed.Report, Command);
      end if;
      return
        Improve.Presentation.Verification
          (To_String (Executed.Plan.Plan_Id), Executed.Report, Command);
   end Verify_Output;

   function Refresh_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Ignored     : Boolean;
   begin
      Improve.Operations.Reconciliation.Run
        (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
         To_String (Settings.Task_Kind),
         Improve.Operations.Storage_Read_Limits (Settings),
         Improve.Operations.Quality_Load_Limits (Settings),
         Improve.Config.Evidence_Limits_Of (Settings));
      return Verify_Output (Item, Settings, Ignored, Command => "refresh");
   end Refresh_Output;

   function Dispatch
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Negative : out Boolean) return String is
      Plain : Unbounded_String;
   begin
      Negative := False;
      Improve.Presentation.Configure (Item.Format, Item.Color);
      case Item.Command is
         when Help_Command => Plain := To_Unbounded_String (Help_Text);
         when Version_Command =>
            Plain := To_Unbounded_String (Message ("help.version", [Arg ("version", Version)]) & LF);
         when Config_Command =>
            if Item.Has_Target and then To_String (Item.Target) = "validate" then
               if Length (Settings.Source_Path) = 0 then
                  raise Argument_Error with "no configuration file was selected";
               end if;
               Plain := To_Unbounded_String (Message ("config.valid") & LF);
            else
               Plain := To_Unbounded_String
                 (Improve.Presentation.Header (Message ("config.title")) & LF & Improve.Config.Image (Settings));
            end if;
         when Projects_Command => return Projects_Output (Item, Settings);
         when Findings_Command => return Findings_Output (Item, Settings);
         when Plan_Command => return Plan_Output (Item, Settings);
         when Apply_Command => return Apply_Output (Item, Settings);
         when Tasks_Command => return Tasks_Output (Item, Settings);
         when Status_Command => return Status_Output (Item, Settings);
         when Verify_Command => return Verify_Output (Item, Settings, Negative);
         when Refresh_Command => return Refresh_Output (Item, Settings);
         when Recover_Command => return Recover_Output (Item, Settings);
      end case;
      if Item.Format = JSON_Format then
         return JSON_Output (Name (Item.Command), "text", To_String (Plain));
      end if;
      return To_String (Plain);
   end Dispatch;

   type Error_Category is (Invalid_Input, Unavailable_Dependency, Invalid_State, Internal_Failure);

   function Diagnostic (Category : Error_Category; Detail : String) return String is
      Key : constant String :=
        (case Category is
            when Invalid_Input => "error.argument",
            when Unavailable_Dependency => "error.dependency",
            when Invalid_State => "error.data",
            when Internal_Failure => "error.internal");
      Rendered : constant String :=
        Message (Key, [Arg ("detail", Improve.Presentation.Safe_Text (Detail))]);
   begin
      return Message ("error.prefix", [Arg ("message", Rendered)]) & LF;
   end Diagnostic;

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Item : Invocation;
      Negative : Boolean := False;
   begin
      Item := Parse (Arguments);
      declare Settings : constant Improve.Config.Settings :=
        Improve.Config.Load (Configuration_Path (Item));
      begin
         if not Item.Has_Format then Item.Format := Settings.Format; end if;
         if not Item.Has_Color then Item.Color := Settings.Color; end if;
         if Item.Format = JSON_Format then Item.Color := Color_Never; end if;
         declare
            Base_Output : constant String := Dispatch (Item, Settings, Negative);
            Output      : Unbounded_String := To_Unbounded_String (Base_Output);
         begin
            if Item.Format = Terminal_Format and then Item.Quiet then
               Output := Null_Unbounded_String;
            elsif Item.Format = Terminal_Format and then Item.Verbose then
               Append
                 (Output,
                  Message
                    ("verbose.context",
                     [Arg ("command", Name (Item.Command)),
                      Arg ("database", Improve.Presentation.Safe_Text (Quality_Path (Item, Settings))),
                      Arg ("state", Improve.Presentation.Safe_Text (State_Path (Item)))]) & LF);
            end if;
            return
              ((if Negative then Negative_Exit else Success_Exit),
               Output, Null_Unbounded_String);
         end;
      end;
   exception
      when Error : Argument_Error =>
         return (Argument_Exit, Null_Unbounded_String,
                 To_Unbounded_String
                   (Diagnostic (Invalid_Input, Ada.Exceptions.Exception_Message (Error)) &
                    Message ("error.hint") & LF));
      when Error : Dependency_Error =>
         return (Unavailable_Exit, Null_Unbounded_String,
                 To_Unbounded_String
                   (Diagnostic (Unavailable_Dependency, Ada.Exceptions.Exception_Message (Error))));
      when Error : Data_Error =>
         return (Failure_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Invalid_State, Ada.Exceptions.Exception_Message (Error))));
      when Error : others =>
         return (Failure_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Internal_Failure, Ada.Exceptions.Exception_Message (Error))));
   end Execute;

   procedure Write (Text : String) is
      Stream : constant Ada.Text_IO.Text_Streams.Stream_Access :=
        Ada.Text_IO.Text_Streams.Stream (Ada.Text_IO.Standard_Output);
   begin
      String'Write (Stream, Text);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
   end Write;

   function Run return Natural is
      Arguments : String_Vectors.Vector;
   begin
      for Index in 1 .. Ada.Command_Line.Argument_Count loop
         Arguments.Append (Ada.Command_Line.Argument (Index));
      end loop;
      declare
         Result : constant Outcome := Execute (Arguments);
      begin
         if Length (Result.Errors) > 0 then
            Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, To_String (Result.Errors));
         end if;
         if Length (Result.Output) > 0 then Write (To_String (Result.Output)); end if;
         return Result.Exit_Code;
      exception
         when Error : Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.End_Error |
              Ada.IO_Exceptions.Status_Error =>
            Ada.Text_IO.Put (Ada.Text_IO.Standard_Error,
              Diagnostic (Invalid_State,
                Message ("error.output", [Arg ("message", Ada.Exceptions.Exception_Message (Error))])));
            return Failure_Exit;
      end;
   end Run;
end Improve.CLI;

