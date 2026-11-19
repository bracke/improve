with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Improve.CLI.Parsing is
   use Ada.Strings.Unbounded;
   use Improve.Config;

   procedure Fail (Message : String) is
   begin
      raise Improve.Argument_Error with Message;
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
      Result       : Invocation;
      Has_Command  : Boolean := False;
      Help_Flag    : Boolean := False;
      Version_Flag : Boolean := False;
      Seen_Format, Seen_Color, Seen_Verbose, Seen_Quiet, Seen_Dry, Seen_All : Boolean := False;
      Seen_Release, Seen_No_Agent : Boolean := False;
      Index : Positive := 1;

      procedure Once (Seen : in out Boolean; Option : String) is
      begin
         if Seen then
            Fail ("option " & Option & " was given more than once");
         end if;
         Seen := True;
      end Once;

      function Value_Of (Option, Inline : String; Has_Inline : Boolean) return String is
      begin
         if Has_Inline then
            if Inline = "" then
               Fail ("option " & Option & " requires a value");
            end if;
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
         if Has_Inline then
            Fail ("option " & Option & " does not take a value");
         end if;
      end No_Value;

      procedure Handle_Option (Item : String) is
         Equals : constant Natural := Ada.Strings.Fixed.Index (Item, "=");
         Option : constant String := (if Equals = 0 then Item else Item (Item'First .. Equals - 1));
         Inline : constant String := (if Equals = 0 then "" else Item (Equals + 1 .. Item'Last));
         Has_Inline : constant Boolean := Equals /= 0;
      begin
         if Option = "--help" then
            No_Value (Option, Has_Inline);
            Help_Flag := True;
         elsif Option = "--version" then
            No_Value (Option, Has_Inline);
            Version_Flag := True;
         elsif Option = "--database" then
            Once (Result.Has_Database, Option);
            Result.Database := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--config" then
            Once (Result.Has_Config, Option);
            Result.Config := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--state" then
            Once (Result.Has_State, Option);
            Result.State := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--project" then
            Once (Result.Has_Project, Option);
            Result.Project := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--format" then
            Once (Seen_Format, Option);
            Result.Has_Format := True;
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "terminal" then
                  Result.Format := Terminal_Format;
               elsif Value = "json" then
                  Result.Format := JSON_Format;
               elsif Value = "markdown" then
                  Result.Format := Markdown_Format;
               elsif Value = "dot" then
                  Result.Format := DOT_Format;
               else
                  Fail ("invalid --format value " & Value & "; expected terminal, json, markdown, or dot");
               end if;
            end;
         elsif Option = "--color" then
            Once (Seen_Color, Option);
            Result.Has_Color := True;
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "auto" then
                  Result.Color := Color_Auto;
               elsif Value = "always" then
                  Result.Color := Color_Always;
               elsif Value = "never" then
                  Result.Color := Color_Never;
               else
                  Fail ("invalid --color value " & Value & "; expected auto, always, or never");
               end if;
            end;
         elsif Option = "--progress" then
            Once (Result.Has_Progress, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "auto" then
                  Result.Progress := Progress_Auto;
               elsif Value = "always" then
                  Result.Progress := Progress_Always;
               elsif Value = "never" then
                  Result.Progress := Progress_Never;
               else
                  Fail ("invalid --progress value " & Value & "; expected auto, always, or never");
               end if;
            end;
         elsif Option = "--run" then
            Once (Result.Has_Run, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail ("--run requires a positive run identity");
               end if;
               Result.Run_Id := Natural'Value (Value);
               if Result.Run_Id = 0 then
                  Fail ("--run requires a positive run identity");
               end if;
            exception
               when Constraint_Error =>
                  Fail ("--run value is out of range");
            end;
         elsif Option = "--revision" then
            Once (Result.Has_Revision, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail ("--revision requires a positive revision");
               end if;
               Result.Revision := Natural'Value (Value);
               if Result.Revision = 0 then
                  Fail ("--revision requires a positive revision");
               end if;
            exception
               when Constraint_Error =>
                  Fail ("--revision value is out of range");
            end;
         elsif Option = "--against-revision" then
            Once (Result.Has_Against_Revision, Option);
            declare
               Value : constant String := Value_Of (Option, Inline, Has_Inline);
            begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail ("--against-revision requires a positive revision");
               end if;
               Result.Against_Revision := Natural'Value (Value);
               if Result.Against_Revision = 0 then
                  Fail ("--against-revision requires a positive revision");
               end if;
            exception
               when Constraint_Error => Fail ("--against-revision value is out of range");
            end;
         elsif Option = "--task" then
            Once (Result.Has_Task, Option);
            Result.Task_Id := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option in "--limit" | "--cursor" then
            if Option = "--limit" then Once (Result.Has_Limit, Option); else Once (Result.Has_Cursor, Option); end if;
            declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail (Option & " requires a nonnegative integer");
               end if;
               if Option = "--limit" then
                  Result.Limit := Natural'Value (Value);
                  if Result.Limit = 0 then Fail ("--limit requires a positive integer"); end if;
               else
                  Result.Cursor := Natural'Value (Value);
               end if;
            exception
               when Constraint_Error => Fail (Option & " value is out of range");
            end;
         elsif Option = "--status" then
            Once (Result.Has_Status, Option);
            Result.Status_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--indicator" then
            Once (Result.Has_Indicator, Option);
            Result.Indicator_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--severity" then
            Once (Result.Has_Severity, Option);
            Result.Severity_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--path" then
            Once (Result.Has_Path, Option);
            Result.Path_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--signing-key" then
            Once (Result.Has_Signing_Key, Option);
            Result.Signing_Key := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--agent-model" then
            Once (Result.Has_Agent_Model, Option);
            Result.Agent_Model := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--agent-model-path" then
            Once (Result.Has_Agent_Model_Path, Option);
            Result.Agent_Model_Path := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--agent-model-sha256" then
            Once (Result.Has_Agent_Model_SHA256, Option);
            Result.Agent_Model_SHA256 := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--no-agent" then
            No_Value (Option, Has_Inline);
            Once (Seen_No_Agent, Option);
            Result.No_Agent := True;
         elsif Option = "--dry-run" then
            No_Value (Option, Has_Inline);
            Once (Seen_Dry, Option);
            Result.Dry_Run := True;
         elsif Option = "--all" then
            No_Value (Option, Has_Inline);
            Once (Seen_All, Option);
            Result.All_Projects := True;
         elsif Option = "--release" then
            No_Value (Option, Has_Inline);
            Once (Seen_Release, Option);
            Result.Release_Check := True;
         elsif Option = "--verbose" then
            No_Value (Option, Has_Inline);
            Once (Seen_Verbose, Option);
            Result.Verbose := True;
         elsif Option = "--quiet" then
            No_Value (Option, Has_Inline);
            Once (Seen_Quiet, Option);
            Result.Quiet := True;
         else
            Fail ("unknown option " & Option);
         end if;
      end Handle_Option;

      procedure Handle_Positional (Item : String) is
         Parsed : Command_Kind;
      begin
         if not Has_Command then
            if not Parse_Command (Item, Parsed) then
               Fail ("unknown command " & Item);
            end if;
            Result.Command := Parsed;
            Has_Command := True;
         elsif Result.Command = Help_Command and then not Result.Has_Target then
            if not Parse_Command (Item, Parsed) then
               Fail ("unknown help topic " & Item);
            end if;
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Plan_Command and then Result.Plan_Action = Create_Plan and then
           Item in "list" | "show" | "approve" | "diff" | "explain" | "graph"
         then
            Result.Plan_Action :=
              (if Item = "list" then List_Plans
               elsif Item = "show" then Show_Plan
               elsif Item = "approve" then Approve_Plan
               elsif Item = "diff" then Diff_Plan
               elsif Item = "explain" then Explain_Plan
               else Graph_Plan);
         elsif Result.Command = Plan_Command and then
           Result.Plan_Action in Show_Plan | Approve_Plan | Diff_Plan | Explain_Plan | Graph_Plan and then
           not Result.Has_Target
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Apply_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Audit_Command and then Item = "verify" and then not Result.Has_Target then
            Result.Audit_Verify := True;
         elsif Result.Command = Audit_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Config_Command and then not Result.Has_Target and then
           Item in "show" | "validate" | "explain"
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Completion_Command and then not Result.Has_Target and then
           Item in "bash" | "zsh" | "fish"
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         else
            Fail ("unexpected argument " & Item);
         end if;
      end Handle_Positional;
   begin
      while Index <= Natural (Arguments.Length) loop
         declare
            Item : constant String := Arguments (Index);
         begin
            if Item'Length >= 2 and then Item (Item'First .. Item'First + 1) = "--" then
               Handle_Option (Item);
            else
               Handle_Positional (Item);
            end if;
         end;
         Index := Index + 1;
      end loop;
      if Help_Flag then
         if Has_Command and then Result.Command /= Help_Command then
            Result.Target := To_Unbounded_String (Name (Result.Command));
            Result.Has_Target := True;
         end if;
         Result.Command := Help_Command;
      elsif Version_Flag then
         if Has_Command then
            Fail ("--version cannot be combined with a command");
         end if;
         Result.Command := Version_Command;
      elsif not Has_Command then
         Fail ("a command is required");
      end if;
      if Result.Verbose and Result.Quiet then
         Fail ("--verbose and --quiet are mutually exclusive");
      end if;
      if Result.Quiet and then Result.Progress = Progress_Always then
         Fail ("--quiet and --progress=always are mutually exclusive");
      end if;
      if Result.Format = JSON_Format then
         Result.Color := Color_Never;
      end if;
      if Result.Has_Run and then Result.Command not in Findings_Command | Plan_Command | Verify_Command then
         Fail ("--run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Revision and then
        not (Result.Command = Plan_Command and then
             Result.Plan_Action in Show_Plan | Diff_Plan | Explain_Plan | Graph_Plan) and then
        not (Result.Command = Tasks_Command and then Result.Has_Task) and then Result.Command /= Verify_Command and then
        Result.Command /= Audit_Command
      then
         Fail ("--revision requires plan show, tasks --task, or verify");
      elsif Result.Dry_Run and then Result.Command not in Plan_Command | Apply_Command then
         Fail ("--dry-run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Task and then Result.Command not in Apply_Command | Tasks_Command | Verify_Command then
         Fail ("--task is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Status and then Result.Command /= Tasks_Command then
         Fail ("--status is not accepted by command " & Name (Result.Command));
      elsif (Result.Has_Indicator or else Result.Has_Severity or else Result.Has_Path) and then
        Result.Command /= Findings_Command
      then
         Fail ("finding filters are accepted only by command findings");
      elsif Result.Has_Against_Revision and then
        not (Result.Command = Plan_Command and then Result.Plan_Action = Diff_Plan)
      then
         Fail ("--against-revision requires plan diff");
      elsif Result.All_Projects and then Result.Command /= Status_Command then
         Fail ("--all is not accepted by command " & Name (Result.Command));
      elsif Result.Release_Check and then Result.Command /= Doctor_Command then
         Fail ("--release is accepted only by command doctor");
      elsif Result.Has_Signing_Key and then (Result.Command /= Audit_Command or else Result.Audit_Verify) then
         Fail ("--signing-key is accepted only by audit export");
      elsif Result.No_Agent and then
        (Result.Has_Agent_Model or else Result.Has_Agent_Model_Path or else Result.Has_Agent_Model_SHA256)
      then
         Fail ("--no-agent cannot be combined with agent model overrides");
      elsif (Result.Has_Limit or else Result.Has_Cursor) and then
        not (Result.Command in Findings_Command | Tasks_Command | Audit_Command or else
             (Result.Command = Plan_Command and then Result.Plan_Action = List_Plans))
      then
         Fail ("pagination is accepted only by findings, tasks, plan list, and audit");
      elsif Result.Format = DOT_Format and then
        not (Result.Command = Plan_Command and then Result.Plan_Action = Graph_Plan)
      then
         Fail ("--format dot requires plan graph");
      end if;
      if Result.Command = Apply_Command and then not Result.Has_Target then
         Fail ("apply requires a plan identity");
      elsif Result.Command = Audit_Command and then not Result.Has_Target then
         Fail (if Result.Audit_Verify then "audit verify requires a file" else "audit requires a plan identity");
      elsif Result.Command = Plan_Command and then
        Result.Plan_Action in Show_Plan | Approve_Plan | Diff_Plan | Explain_Plan | Graph_Plan and then
        not Result.Has_Target
      then
         Fail
           ("plan " &
            (case Result.Plan_Action is
                when Show_Plan => "show", when Approve_Plan => "approve", when Diff_Plan => "diff",
                when Explain_Plan => "explain", when Graph_Plan => "graph", when others => "create") &
            " requires a plan identity");
      elsif Result.Command = Plan_Command and then Result.Plan_Action = Diff_Plan and then
        (not Result.Has_Revision or else not Result.Has_Against_Revision)
      then
         Fail ("plan diff requires --against-revision and --revision");
      elsif Result.Command in Findings_Command | Refresh_Command and then not Result.Has_Project then
         Fail (Name (Result.Command) & " requires --project");
      elsif Result.Command = Tasks_Command and then not Result.Has_Project and then not Result.Has_Task then
         Fail ("tasks requires --project or --task");
      elsif Result.Command = Plan_Command and then
        Result.Plan_Action in Create_Plan | List_Plans and then not Result.Has_Project
      then
         Fail ("plan requires --project");
      elsif Result.Command = Verify_Command and then not Result.Has_Project and then not Result.Has_Task then
         Fail ("verify requires --project or --task");
      elsif Result.Command = Status_Command and then Result.Has_Project = Result.All_Projects then
         Fail ("status requires exactly one of --project or --all");
      elsif Result.Command = Completion_Command and then not Result.Has_Target then
         Fail ("completion requires bash, zsh, or fish");
      end if;
      return Result;
   end Parse;
end Improve.CLI.Parsing;
