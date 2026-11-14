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
               else
                  Fail ("invalid --format value " & Value & "; expected terminal or json");
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
         elsif Option = "--task" then
            Once (Result.Has_Task, Option);
            Result.Task_Id := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--status" then
            Once (Result.Has_Status, Option);
            Result.Status_Filter := To_Unbounded_String (Value_Of (Option, Inline, Has_Inline));
         elsif Option = "--dry-run" then
            No_Value (Option, Has_Inline);
            Once (Seen_Dry, Option);
            Result.Dry_Run := True;
         elsif Option = "--all" then
            No_Value (Option, Has_Inline);
            Once (Seen_All, Option);
            Result.All_Projects := True;
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
           Item in "list" | "show" | "approve"
         then
            Result.Plan_Action :=
              (if Item = "list" then List_Plans elsif Item = "show" then Show_Plan else Approve_Plan);
         elsif Result.Command = Plan_Command and then
           Result.Plan_Action in Show_Plan | Approve_Plan and then not Result.Has_Target
         then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Apply_Command and then not Result.Has_Target then
            Result.Target := To_Unbounded_String (Item);
            Result.Has_Target := True;
         elsif Result.Command = Config_Command and then not Result.Has_Target and then Item in "show" | "validate" then
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
      if Result.Format = JSON_Format then
         Result.Color := Color_Never;
      end if;
      if Result.Has_Run and then Result.Command not in Findings_Command | Plan_Command | Verify_Command then
         Fail ("--run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Revision and then
        not (Result.Command = Plan_Command and then Result.Plan_Action = Show_Plan) and then
        not (Result.Command = Tasks_Command and then Result.Has_Task) and then Result.Command /= Verify_Command
      then
         Fail ("--revision requires plan show, tasks --task, or verify");
      elsif Result.Dry_Run and then Result.Command not in Plan_Command | Apply_Command then
         Fail ("--dry-run is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Task and then Result.Command not in Apply_Command | Tasks_Command | Verify_Command then
         Fail ("--task is not accepted by command " & Name (Result.Command));
      elsif Result.Has_Status and then Result.Command /= Tasks_Command then
         Fail ("--status is not accepted by command " & Name (Result.Command));
      elsif Result.All_Projects and then Result.Command /= Status_Command then
         Fail ("--all is not accepted by command " & Name (Result.Command));
      end if;
      if Result.Command = Apply_Command and then not Result.Has_Target then
         Fail ("apply requires a plan identity");
      elsif Result.Command = Plan_Command and then
        Result.Plan_Action in Show_Plan | Approve_Plan and then not Result.Has_Target
      then
         Fail
           ("plan " & (if Result.Plan_Action = Show_Plan then "show" else "approve") &
            " requires a plan identity");
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
      end if;
      return Result;
   end Parse;
end Improve.CLI.Parsing;
