with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.CLI_Metadata;

package body Improve.CLI.Parsing is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use type Improve.CLI_Metadata.Option_Kind;

   procedure Fail (Message : String) is
   begin
      raise Improve.Argument_Error with Message;
   end Fail;

   function Parse (Arguments : String_Vectors.Vector) return Invocation is
      Result       : Invocation;
      Has_Command  : Boolean := False;
      Help_Flag    : Boolean := False;
      Version_Flag : Boolean := False;
      Seen_Format, Seen_Color, Seen_Verbose, Seen_Quiet, Seen_Dry, Seen_All : Boolean := False;
      Seen_Release, Seen_No_Agent : Boolean := False;
      Context : Improve.CLI_Metadata.Operation_Context := Improve.CLI_Metadata.No_Operation;
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
         Kind : Improve.CLI_Metadata.Option_Kind;
      begin
         if not Improve.CLI_Metadata.Parse_Option (Option, Kind) then
            Fail ("unknown option " & Option);
         end if;
         case Kind is
            when Improve.CLI_Metadata.Help_Option =>
               No_Value (Option, Has_Inline);
               Help_Flag := True;
            when Improve.CLI_Metadata.Version_Option =>
               No_Value (Option, Has_Inline);
               Version_Flag := True;
            when Improve.CLI_Metadata.Database_Option =>
               Once (Result.Has_Database, Option);
               Result.Database := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Config_Option =>
               Once (Result.Has_Config, Option);
               Result.Config := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.State_Option =>
               Once (Result.Has_State, Option);
               Result.State := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Project_Option =>
               Once (Result.Has_Project, Option);
               Result.Project := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Format_Option =>
               Once (Seen_Format, Option);
               Result.Has_Format := True;
               declare
                  Value : constant String := Value_Of (Option, Inline, Has_Inline);
               begin
                  if not Improve.Config.Parse_Output_Format (Value, Result.Format) then
                     Fail
                       ("invalid --format value " & Value & "; expected " &
                        Improve.CLI_Metadata.Value_Expectation (Kind));
                  end if;
               end;
            when Improve.CLI_Metadata.Color_Option =>
               Once (Seen_Color, Option);
               Result.Has_Color := True;
               declare
                  Value : constant String := Value_Of (Option, Inline, Has_Inline);
               begin
                  if not Improve.Config.Parse_Color_Mode (Value, Result.Color) then
                     Fail
                       ("invalid --color value " & Value & "; expected " &
                        Improve.CLI_Metadata.Value_Expectation (Kind));
                  end if;
               end;
            when Improve.CLI_Metadata.Progress_Option =>
               Once (Result.Has_Progress, Option);
               declare
                  Value : constant String := Value_Of (Option, Inline, Has_Inline);
               begin
                  if not Improve.CLI_Metadata.Parse_Progress_Mode (Value, Result.Progress) then
                     Fail
                       ("invalid --progress value " & Value & "; expected " &
                        Improve.CLI_Metadata.Value_Expectation (Kind));
                  end if;
               end;
            when Improve.CLI_Metadata.Run_Option =>
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
            when Improve.CLI_Metadata.Revision_Option =>
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
            when Improve.CLI_Metadata.Against_Revision_Option =>
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
            when Improve.CLI_Metadata.Task_Option =>
               Once (Result.Has_Task, Option);
               Result.Task_Id := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Limit_Option | Improve.CLI_Metadata.Cursor_Option =>
               if Kind = Improve.CLI_Metadata.Limit_Option then
                  Once (Result.Has_Limit, Option);
               else
                  Once (Result.Has_Cursor, Option);
               end if;
               declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
                  if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                     Fail (Option & " requires a nonnegative integer");
                  end if;
                  if Kind = Improve.CLI_Metadata.Limit_Option then
                     Result.Limit := Natural'Value (Value);
                     if Result.Limit = 0 then Fail ("--limit requires a positive integer"); end if;
                  else
                     Result.Cursor := Natural'Value (Value);
                  end if;
               exception
                  when Constraint_Error => Fail (Option & " value is out of range");
               end;
            when Improve.CLI_Metadata.Status_Option =>
               Once (Result.Has_Status, Option);
               Result.Status_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Indicator_Option =>
               Once (Result.Has_Indicator, Option);
               Result.Indicator_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Severity_Option =>
               Once (Result.Has_Severity, Option);
               Result.Severity_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Path_Option =>
               Once (Result.Has_Path, Option);
               Result.Path_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Signing_Key_Option =>
               Once (Result.Has_Signing_Key, Option);
               Result.Signing_Key := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Verification_Key_Option =>
               Once (Result.Has_Verification_Key, Option);
               Result.Verification_Key := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Agent_Model_Option =>
               Once (Result.Has_Agent_Model, Option);
               Result.Agent_Model := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Agent_Model_Path_Option =>
               Once (Result.Has_Agent_Model_Path, Option);
               Result.Agent_Model_Path := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.Agent_Model_SHA256_Option =>
               Once (Result.Has_Agent_Model_SHA256, Option);
               Result.Agent_Model_SHA256 := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
            when Improve.CLI_Metadata.No_Agent_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_No_Agent, Option);
               Result.No_Agent := True;
            when Improve.CLI_Metadata.Dry_Run_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_Dry, Option);
               Result.Dry_Run := True;
            when Improve.CLI_Metadata.All_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_All, Option);
               Result.All_Projects := True;
            when Improve.CLI_Metadata.Release_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_Release, Option);
               Result.Release_Check := True;
            when Improve.CLI_Metadata.Verbose_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_Verbose, Option);
               Result.Verbose := True;
            when Improve.CLI_Metadata.Quiet_Option =>
               No_Value (Option, Has_Inline);
               Once (Seen_Quiet, Option);
               Result.Quiet := True;
         end case;
      end Handle_Option;

      procedure Handle_Positional (Item : String) is
         Parsed           : Command_Kind;
         Parsed_Operation : Plan_Operation;
         Is_Operation     : constant Boolean :=
           Improve.CLI_Metadata.Parse_Plan_Operation (Item, Parsed_Operation);
      begin
         if not Has_Command then
            if not Improve.CLI_Metadata.Parse_Command (Item, Parsed) then
               Fail ("unknown command " & Item);
            end if;
            Result.Command := Parsed;
            Has_Command := True;
         elsif Result.Command = Help_Command and then not Result.Has_Target then
            if not Improve.CLI_Metadata.Parse_Command (Item, Parsed) then
               Fail ("unknown help topic " & Item);
            end if;
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Plan_Command and then Result.Plan_Action = Create_Plan and then Is_Operation
         then
            Result.Plan_Action := Parsed_Operation;
         elsif Result.Command = Plan_Command and then
           Result.Plan_Action in Show_Plan | Approve_Plan | Diff_Plan | Explain_Plan | Graph_Plan and then
           not Result.Has_Target
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Apply_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Audit_Command and then not Result.Has_Target and then
           Improve.CLI_Metadata.Positional_Value_Allowed (Result.Command, Item)
         then
            Result.Audit_Verify := True;
         elsif Result.Command = Audit_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Config_Command and then not Result.Has_Target and then
           Improve.CLI_Metadata.Positional_Value_Allowed (Result.Command, Item)
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Completion_Command and then not Result.Has_Target and then
           Improve.CLI_Metadata.Positional_Value_Allowed (Result.Command, Item)
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
      Context := Improve.CLI_Metadata.Context_For (Result.Command, Result.Plan_Action, Result.Audit_Verify);
      if Result.Verbose and Result.Quiet then
         Fail ("--verbose and --quiet are mutually exclusive");
      end if;
      if Result.Quiet and then Result.Progress = Progress_Always then
         Fail ("--quiet and --progress=always are mutually exclusive");
      end if;
      if Result.Format = JSON_Format then
         Result.Color := Color_Never;
      end if;
      if Result.Has_Run and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Run_Option, Result.Command)
      then
         Fail ("--run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Revision and then
        (not Improve.CLI_Metadata.Accepted_In_Context
           (Improve.CLI_Metadata.Revision_Option, Result.Command, Context) or else
         (Result.Command = Tasks_Command and then not Result.Has_Task))
      then
         Fail ("--revision requires plan show, tasks --task, or verify");
      elsif Result.Dry_Run and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Dry_Run_Option, Result.Command)
      then
         Fail ("--dry-run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Task and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Task_Option, Result.Command)
      then
         Fail ("--task is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Status and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Status_Option, Result.Command)
      then
         Fail ("--status is not accepted by command " & Name (Result.Command));
      elsif (Result.Has_Indicator or else Result.Has_Severity or else Result.Has_Path) and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Indicator_Option, Result.Command)
      then
         Fail ("finding filters are accepted only by command findings");
      elsif Result.Has_Against_Revision and then
        not Improve.CLI_Metadata.Accepted_In_Context
          (Improve.CLI_Metadata.Against_Revision_Option, Result.Command, Context)
      then
         Fail ("--against-revision requires plan diff");
      elsif Result.All_Projects and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.All_Option, Result.Command)
      then
         Fail ("--all is not accepted by command " & Name (Result.Command));
      elsif Result.Release_Check and then
        not Improve.CLI_Metadata.Accepted_By_Command (Improve.CLI_Metadata.Release_Option, Result.Command)
      then
         Fail ("--release is accepted only by command doctor");
      elsif Result.Has_Signing_Key and then
        not Improve.CLI_Metadata.Accepted_In_Context
          (Improve.CLI_Metadata.Signing_Key_Option, Result.Command, Context)
      then
         Fail ("--signing-key is accepted only by audit export");
      elsif Result.Has_Verification_Key and then
        not Improve.CLI_Metadata.Accepted_In_Context
          (Improve.CLI_Metadata.Verification_Key_Option, Result.Command, Context)
      then
         Fail ("--verification-key is accepted only by audit verify");
      elsif Result.No_Agent and then
        (Result.Has_Agent_Model or else Result.Has_Agent_Model_Path or else Result.Has_Agent_Model_SHA256)
      then
         Fail ("--no-agent cannot be combined with agent model overrides");
      elsif (Result.Has_Limit or else Result.Has_Cursor) and then
        not Improve.CLI_Metadata.Accepted_In_Context
          (Improve.CLI_Metadata.Limit_Option, Result.Command, Context)
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
            Improve.CLI_Metadata.Plan_Operation_Name (Result.Plan_Action) &
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
