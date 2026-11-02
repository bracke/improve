with Ada.Command_Line;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Improve.Presentation;
with Improve.Text;
with Jsonlib.Documents;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Improve.CLI is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use Improve.Text;

   LF : constant Character := Character'Val (10);

   function Name (Command : Command_Kind) return String is
     (case Command is
         when Projects_Command => "projects", when Findings_Command => "findings", when Plan_Command => "plan",
         when Apply_Command => "apply", when Tasks_Command => "tasks", when Status_Command => "status",
         when Refresh_Command => "refresh", when Verify_Command => "verify", when Recover_Command => "recover",
         when Config_Command => "config", when Help_Command => "help", when Version_Command => "version");

   procedure Fail (Message : String) is
   begin
      raise Argument_Error with Message;
   end Fail;

   function Parse_Command (Text : String; Command : out Command_Kind) return Boolean is
   begin
      for Candidate in Command_Kind loop
         if Name (Candidate) = Text then
            Command := Candidate;
            return True;
         end if;
      end loop;
      Command := Help_Command;
      return False;
   end Parse_Command;

   function Parse (Arguments : String_Vectors.Vector) return Invocation is
      Result      : Invocation;
      Has_Command : Boolean := False;
      Help_Flag   : Boolean := False;
      Version_Flag : Boolean := False;
      Seen_Format, Seen_Color, Seen_Verbose, Seen_Quiet, Seen_Dry, Seen_All : Boolean := False;
      Index       : Positive := 1;

      procedure Once (Seen : in out Boolean; Option : String) is
      begin
         if Seen then Fail ("option " & Option & " was given more than once"); end if;
         Seen := True;
      end Once;

      function Value_Of (Option, Inline : String; Has_Inline : Boolean) return String is
      begin
         if Has_Inline then
            if Inline = "" then Fail ("option " & Option & " requires a value"); end if;
            return Inline;
         elsif Index >= Natural (Arguments.Length) then
            Fail ("option " & Option & " requires a value");
         end if;
         declare
            Following : constant String := Arguments (Index + 1);
         begin
            if Following'Length >= 2 and then Following (Following'First .. Following'First + 1) = "--" then
               Fail ("option " & Option & " requires a value");
            end if;
         end;
         Index := Index + 1;
         return Arguments (Index);
      end Value_Of;

      procedure No_Value (Option : String; Has_Inline : Boolean) is
      begin
         if Has_Inline then Fail ("option " & Option & " does not take a value"); end if;
      end No_Value;

      procedure Handle_Option (Item : String) is
         Equals     : constant Natural := Ada.Strings.Fixed.Index (Item, "=");
         Option     : constant String := (if Equals = 0 then Item else Item (Item'First .. Equals - 1));
         Inline     : constant String := (if Equals = 0 then "" else Item (Equals + 1 .. Item'Last));
         Has_Inline : constant Boolean := Equals /= 0;
      begin
         if Option = "--help" then
            No_Value (Option, Has_Inline); Help_Flag := True;
         elsif Option = "--version" then
            No_Value (Option, Has_Inline); Version_Flag := True;
         elsif Option = "--database" then
            Once (Result.Has_Database, Option);
            Result.Database := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--state" then
            Once (Result.Has_State, Option);
            Result.State := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--project" then
            Once (Result.Has_Project, Option);
            Result.Project := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--format" then
            Once (Seen_Format, Option);
            declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
               if Value = "terminal" then Result.Format := Terminal_Format;
               elsif Value = "json" then Result.Format := JSON_Format;
               else Fail ("invalid --format value " & Value & "; expected terminal or json");
               end if;
            end;
         elsif Option = "--color" then
            Once (Seen_Color, Option);
            declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
               if Value = "auto" then Result.Color := Color_Auto;
               elsif Value = "always" then Result.Color := Color_Always;
               elsif Value = "never" then Result.Color := Color_Never;
               else Fail ("invalid --color value " & Value & "; expected auto, always, or never");
               end if;
            end;
         elsif Option = "--run" then
            Once (Result.Has_Run, Option);
            declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail ("--run requires a positive run identity");
               end if;
               Result.Run_Id := Natural'Value (Value);
               if Result.Run_Id = 0 then Fail ("--run requires a positive run identity"); end if;
            exception when Constraint_Error => Fail ("--run value is out of range"); end;
         elsif Option = "--task" then
            Once (Result.Has_Task, Option);
            Result.Task_Id := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--status" then
            Once (Result.Has_Status, Option);
            Result.Status_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--dry-run" then
            No_Value (Option, Has_Inline); Once (Seen_Dry, Option); Result.Dry_Run := True;
         elsif Option = "--all" then
            No_Value (Option, Has_Inline); Once (Seen_All, Option); Result.All_Projects := True;
         elsif Option = "--verbose" then
            No_Value (Option, Has_Inline); Once (Seen_Verbose, Option); Result.Verbose := True;
         elsif Option = "--quiet" then
            No_Value (Option, Has_Inline); Once (Seen_Quiet, Option); Result.Quiet := True;
         else
            Fail ("unknown option " & Option);
         end if;
      end Handle_Option;

      procedure Handle_Positional (Item : String) is
         Parsed : Command_Kind;
      begin
         if not Has_Command then
            if not Parse_Command (Item, Parsed) then Fail ("unknown command " & Item); end if;
            Result.Command := Parsed;
            Has_Command := True;
         elsif Result.Command = Help_Command and then not Result.Has_Target then
            if not Parse_Command (Item, Parsed) then Fail ("unknown help topic " & Item); end if;
            Result.Target := To_Unbounded_String (Item); Result.Has_Target := True;
         elsif Result.Command = Plan_Command and then Result.Plan_Action = Create_Plan and then
           Item in "list" | "show"
         then
            Result.Plan_Action := (if Item = "list" then List_Plans else Show_Plan);
         elsif Result.Command = Plan_Command and then Result.Plan_Action = Show_Plan and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item); Result.Has_Target := True;
         elsif Result.Command = Apply_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item); Result.Has_Target := True;
         elsif Result.Command = Config_Command and then not Result.Has_Target and then Item in "show" | "validate" then
            Result.Target := To_Unbounded_String (Item); Result.Has_Target := True;
         else
            Fail ("unexpected argument " & Item);
         end if;
      end Handle_Positional;
   begin
      while Index <= Natural (Arguments.Length) loop
         declare Item : constant String := Arguments (Index); begin
            if Item'Length >= 2 and then Item (Item'First .. Item'First + 1) = "--" then Handle_Option (Item);
            else Handle_Positional (Item); end if;
         end;
         Index := Index + 1;
      end loop;
      if Help_Flag then
         if Has_Command and then Result.Command /= Help_Command then
            Result.Target := To_Unbounded_String (Name (Result.Command)); Result.Has_Target := True;
         end if;
         Result.Command := Help_Command;
      elsif Version_Flag then
         if Has_Command then Fail ("--version cannot be combined with a command"); end if;
         Result.Command := Version_Command;
      elsif not Has_Command then
         Fail ("a command is required");
      end if;
      if Result.Verbose and Result.Quiet then Fail ("--verbose and --quiet are mutually exclusive"); end if;
      if Result.Format = JSON_Format then Result.Color := Color_Never; end if;
      if Result.Has_Run and then Result.Command not in Findings_Command | Plan_Command | Verify_Command then
         Fail ("--run is not accepted by command " & Name (Result.Command));
      elsif Result.Dry_Run and then Result.Command not in Plan_Command | Apply_Command then
         Fail ("--dry-run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Task and then Result.Command not in Apply_Command | Verify_Command then
         Fail ("--task is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Status and then Result.Command /= Tasks_Command then
         Fail ("--status is not accepted by command " & Name (Result.Command));
      elsif Result.All_Projects and then Result.Command /= Status_Command then
         Fail ("--all is not accepted by command " & Name (Result.Command));
      end if;
      if Result.Command = Apply_Command and then not Result.Has_Target then
         Fail ("apply requires a plan identity");
      elsif Result.Command = Plan_Command and then Result.Plan_Action = Show_Plan and then not Result.Has_Target then
         Fail ("plan show requires a plan identity");
      elsif Result.Command in Findings_Command | Refresh_Command and then not Result.Has_Project then
         Fail (Name (Result.Command) & " requires --project");
      elsif Result.Command = Plan_Command and then Result.Plan_Action /= Show_Plan and then not Result.Has_Project then
         Fail ("plan requires --project");
      elsif Result.Command = Verify_Command and then not Result.Has_Project and then not Result.Has_Task then
         Fail ("verify requires --project or --task");
      elsif Result.Command = Status_Command and then Result.Has_Project = Result.All_Projects then
         Fail ("status requires exactly one of --project or --all");
      end if;
      return Result;
   end Parse;

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
      Line ("--database PATH", "help.opt.database", 36); Line ("--state PATH", "help.opt.state", 36);
      Line ("--project ID|NAME", "help.opt.project", 36);
      Line ("--format terminal|json", "help.opt.format", 36);
      Line ("--color auto|always|never", "help.opt.color", 36);
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

   function Configuration_Path return String is
     (if Project_Tools.Files.File_Exists ("config/improve.toml") then "config/improve.toml"
      elsif Project_Tools.Files.File_Exists ("../config/improve.toml") then "../config/improve.toml"
      else "");

   function Dispatch (Item : Invocation) return String is
      Plain : Unbounded_String;
   begin
      Improve.Presentation.Configure (Item.Format, Item.Color);
      case Item.Command is
         when Help_Command => Plain := To_Unbounded_String (Help_Text);
         when Version_Command =>
            Plain := To_Unbounded_String (Message ("help.version", [Arg ("version", Version)]) & LF);
         when Config_Command =>
            declare Settings : constant Improve.Config.Settings := Improve.Config.Load (Configuration_Path); begin
               if Item.Has_Target and then To_String (Item.Target) = "validate" then
                  Plain := To_Unbounded_String (Message ("config.valid") & LF);
               else
                  Plain := To_Unbounded_String
                    (Improve.Presentation.Header (Message ("config.title")) & LF & Improve.Config.Image (Settings));
               end if;
            end;
         when others =>
            raise Dependency_Error with Message ("phase.pending", [Arg ("command", Name (Item.Command))]);
      end case;
      if Item.Format = JSON_Format then
         return JSON_Output (Name (Item.Command), "text", To_String (Plain));
      end if;
      return To_String (Plain);
   end Dispatch;

   function Diagnostic (Text : String) return String is
     (Message ("error.prefix", [Arg ("message", Text)]) & LF);

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Item : Invocation;
   begin
      Item := Parse (Arguments);
      return (Success_Exit, To_Unbounded_String (Dispatch (Item)), Null_Unbounded_String);
   exception
      when Error : Argument_Error =>
         return (Argument_Exit, Null_Unbounded_String,
                 To_Unbounded_String
                   (Diagnostic (Ada.Exceptions.Exception_Message (Error)) & Message ("error.hint") & LF));
      when Error : Dependency_Error =>
         return (Unavailable_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Ada.Exceptions.Exception_Message (Error))));
      when Error : Data_Error =>
         return (Failure_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Ada.Exceptions.Exception_Message (Error))));
      when Error : others =>
         return (Failure_Exit, Null_Unbounded_String,
                 To_Unbounded_String (Diagnostic (Message ("error.internal",
                   [Arg ("message", Ada.Exceptions.Exception_Message (Error))]))));
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
              Diagnostic (Message ("error.output", [Arg ("message", Ada.Exceptions.Exception_Message (Error))])));
            return Failure_Exit;
      end;
   end Run;
end Improve.CLI;

