with Ada.Command_Line;
with Ada.Containers;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Improve.Findings;
with Improve.JSON;
with Improve.Model;
with Improve.Planner;
with Improve.Presentation;
with Improve.Recovery;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Improve.Text;
with Improve.Workflow;
with Improve.Verification;
with Jsonlib.Documents;
with Jsonlib.Serializers;
with Project_Tools.Files;

package body Improve.CLI is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use Improve.Text;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Storage.Verification_Scope;
   use type Improve.Tasks.Operational_Status;

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
         elsif Option = "--revision" then
            Once (Result.Has_Revision, Option);
            declare Value : constant String := Value_Of (Option, Inline, Has_Inline); begin
               if Value = "" or else (for some C of Value => C not in '0' .. '9') then
                  Fail ("--revision requires a positive revision");
               end if;
               Result.Revision := Natural'Value (Value);
               if Result.Revision = 0 then Fail ("--revision requires a positive revision"); end if;
            exception when Constraint_Error => Fail ("--revision value is out of range"); end;
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
           Item in "list" | "show" | "approve"
         then
            Result.Plan_Action :=
              (if Item = "list" then List_Plans elsif Item = "show" then Show_Plan else Approve_Plan);
         elsif Result.Command = Plan_Command and then
           Result.Plan_Action in Show_Plan | Approve_Plan and then not Result.Has_Target
         then
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
      elsif Result.Has_Revision and then
        not (Result.Command = Plan_Command and then Result.Plan_Action = Show_Plan) and then
        not (Result.Command = Tasks_Command and then Result.Has_Task) and then
        Result.Command /= Verify_Command
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

   function Configuration_Path return String is
     (if Project_Tools.Files.File_Exists ("config/improve.toml") then "config/improve.toml"
      elsif Project_Tools.Files.File_Exists ("../config/improve.toml") then "../config/improve.toml"
      else "");

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Quality_Severity (Value : Improve.Config.Severity_Level) return Ada_Quality.Types.Severity is
     (case Value is
         when Improve.Config.Info => Ada_Quality.Types.Info,
         when Improve.Config.Low => Ada_Quality.Types.Low,
         when Improve.Config.Medium => Ada_Quality.Types.Medium,
         when Improve.Config.High => Ada_Quality.Types.High,
         when Improve.Config.Critical => Ada_Quality.Types.Critical);

   function Quality_Path (Item : Invocation; Settings : Improve.Config.Settings) return String is
     (if Item.Has_Database then To_String (Item.Database) else To_String (Settings.Quality_Database));

   function State_Path (Item : Invocation) return String is
     (if Item.Has_State then To_String (Item.State) else ".improve.db");

   procedure Require_Project_Identity
     (Stored  : Improve.Model.Project_Reference;
      Current : Improve.Model.Project_Reference) is
   begin
      if Stored.Database_Id /= Current.Database_Id then
         raise Data_Error with "selected Ada Quality database does not own the stored plan";
      elsif Stored.Id /= Current.Id or else Stored.Path /= Current.Path then
         raise Data_Error with "selected Ada Quality project identity does not match the stored plan";
      end if;
   end Require_Project_Identity;

   function Projects_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Store : Improve.Source.Repository;
   begin
      Improve.Source.Open (Store, Quality_Path (Item, Settings));
      declare
         Values   : constant Ada_Quality.Reporting.Project_Vectors.Vector := Improve.Source.Projects (Store);
         Snapshot : constant String := Improve.Source.Identity (Store);
         Result   : Unbounded_String;
      begin
         if Item.Format = JSON_Format then
            Result := To_Unbounded_String (Improve.JSON.Projects (Values, Snapshot));
         else
            Append (Result, Improve.Presentation.Header (Message ("projects.title")) & LF);
            if Values.Is_Empty then
               Append (Result, Message ("projects.none") & LF);
            else
               Append
                 (Result,
                  Message ("label.id") & "  " & Message ("label.enabled") & "  " & Message ("label.path") & LF);
               for Value of Values loop
                  Append
                    (Result,
                     Number (Value.Id) & "   " & (if Value.Enabled then "yes" else "no ") & "      " &
                     To_String (Value.Path) & LF);
               end loop;
            end if;
         end if;
         Improve.Source.Close (Store);
         return To_String (Result);
      end;
   end Projects_Output;

   function Findings_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Store : Improve.Source.Repository;
   begin
      Improve.Source.Open (Store, Quality_Path (Item, Settings));
      declare
         Project  : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Store, To_String (Item.Project));
         Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project, Item.Run_Id);
         Values   : constant Improve.Model.Finding_Vectors.Vector :=
           Improve.Findings.Normalize
             (Selected, Quality_Severity (Settings.Minimum_Severity), Settings.Allow_Investigation_Tasks);
         Result   : Unbounded_String;
      begin
         if Item.Format = JSON_Format then
            Result := To_Unbounded_String (Improve.JSON.Findings (Selected, Values));
         else
            Append
              (Result,
               Improve.Presentation.Header
                 (Message
                    ("findings.title",
                     [Arg ("project", To_String (Project.Name)),
                      Arg ("run", Number (Selected.Assessment.Run.Id))])) & LF);
            if Values.Is_Empty then
               Append (Result, Message ("findings.none") & LF);
            else
               Append
                 (Result,
                  Message ("label.indicator") & "  " & Message ("label.severity") & "  " &
                  Message ("label.location") & "  " & Message ("label.message") & LF);
               for Value of Values loop
                  declare
                     Location : constant String :=
                       (if Length (Value.Relative_Path) = 0 then "-"
                        elsif Value.Line = 0 then To_String (Value.Relative_Path)
                        else To_String (Value.Relative_Path) & ":" & Number (Value.Line));
                  begin
                     Append
                       (Result,
                        Ada_Quality.Types.Image (Value.Indicator) & "  " &
                        Ada_Quality.Types.Severity'Image (Value.Level) & "  " & Location & "  " &
                        To_String (Value.Message) & LF);
                  end;
               end loop;
            end if;
         end if;
         Improve.Source.Close (Store);
         return To_String (Result);
      end;
   end Findings_Output;

   function Plan_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Quality : Improve.Source.Repository;

      function Stored_Plan_Terminal (Plan : Improve.Model.Plan_Revision) return String is
         Result : Unbounded_String;
      begin
         Append
           (Result,
            Improve.Presentation.Header
              (Message
                 ("plan.title",
                  [Arg ("project", To_String (Plan.Project.Name)),
                   Arg ("run", Number (Plan.Baseline.Run_Id))])) & LF);
         Append (Result, Message ("plan.persisted.identity", [Arg ("id", To_String (Plan.Plan_Id))]) & LF);
         Append (Result, Message ("plan.revision", [Arg ("revision", Number (Plan.Revision))]) & LF);
         if Plan.Tasks.Is_Empty then Append (Result, Message ("plan.none") & LF); end if;
         for Spec of Plan.Tasks loop
            Append
              (Result,
               To_String (Spec.Id) & "  [" & Improve.Model.Image (Spec.Task_Priority) & "] " &
               To_String (Spec.Title) & LF & "  " & To_String (Spec.Acceptance) & LF);
         end loop;
         return To_String (Result);
      end Stored_Plan_Terminal;
   begin
      if Item.Plan_Action = Approve_Plan then
         declare
            State : Improve.Storage.Store;
            Plan  : Improve.Model.Plan_Revision;
         begin
            Improve.Storage.Open (State, State_Path (Item), Writable => True);
            Plan := Improve.Storage.Load (State, To_String (Item.Target));
            Improve.Storage.Approve (State, To_String (Plan.Plan_Id), Plan.Revision);
            Improve.Storage.Close (State);
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Approval (Plan); end if;
            return
              Message
                ("plan.approved",
                 [Arg ("id", To_String (Plan.Plan_Id)), Arg ("revision", Number (Plan.Revision))]) & LF;
         end;
      elsif Item.Plan_Action = Show_Plan then
         declare State : Improve.Storage.Store; begin
            Improve.Storage.Open (State, State_Path (Item), Writable => False);
            declare Plan : constant Improve.Model.Plan_Revision :=
              (if Item.Has_Revision then
                  Improve.Storage.Load (State, To_String (Item.Target), Positive (Item.Revision))
               else Improve.Storage.Load (State, To_String (Item.Target)));
            begin
               Improve.Storage.Close (State);
               if Item.Format = JSON_Format then return Improve.JSON.Plan (Plan, Dry_Run => False); end if;
               return Stored_Plan_Terminal (Plan);
            end;
         end;
      elsif Item.Plan_Action = List_Plans then
         Improve.Source.Open (Quality, Quality_Path (Item, Settings));
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
            State : Improve.Storage.Store;
         begin
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path (Item), Writable => False);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project);
            begin
               Improve.Storage.Close (State);
               if Item.Format = JSON_Format then return Improve.JSON.Plans (Values); end if;
               declare Result : Unbounded_String; begin
                  Append (Result, Improve.Presentation.Header (Message ("plan.list.title")) & LF);
                  if Values.Is_Empty then Append (Result, Message ("plan.list.none") & LF); end if;
                  for Value of Values loop
                     Append (Result, To_String (Value.Plan_Id) & "  r" & Number (Value.Revision) & "  " &
                       Number (Value.Task_Count) & " tasks  run " & Number (Value.Run_Id) & LF);
                  end loop;
                  return To_String (Result);
               end;
            end;
         end;
      end if;
      Improve.Source.Open (Quality, Quality_Path (Item, Settings));
      declare
         Project  : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
         Selected : constant Improve.Source.Selection :=
           Improve.Source.Select_Assessment (Quality, Project, Item.Run_Id);
         Findings : constant Improve.Model.Finding_Vectors.Vector :=
           Improve.Findings.Normalize
             (Selected, Quality_Severity (Settings.Minimum_Severity), Settings.Allow_Investigation_Tasks);
         Draft    : constant Improve.Model.Plan_Revision := Improve.Planner.Generate (Selected, Findings, Settings);
         Plan     : Improve.Model.Plan_Revision := Draft;
         Existing : Boolean := False;
         Result   : Unbounded_String;
      begin
         Improve.Source.Close (Quality);
         if not Item.Dry_Run then
            declare
               State : Improve.Storage.Store;
               Saved : Improve.Storage.Save_Result;
            begin
               Improve.Storage.Open (State, State_Path (Item), Writable => True);
               Saved := Improve.Storage.Save (State, Draft);
               Improve.Storage.Close (State);
               Plan := Saved.Plan;
               Existing := Saved.Existing;
            end;
         end if;
         if Item.Format = JSON_Format then
            Result := To_Unbounded_String (Improve.JSON.Plan (Plan, Item.Dry_Run));
         else
            Append
              (Result,
               Improve.Presentation.Header
                 (Message
                    ("plan.title",
                     [Arg ("project", To_String (Project.Name)), Arg ("run", Number (Plan.Baseline.Run_Id))])) & LF);
            Append
              (Result,
               Message
                 ((if Item.Dry_Run then "plan.dry_run" elsif Existing then "plan.existing" else "plan.stored")) & LF);
            Append
              (Result,
               Message
                 ((if Item.Dry_Run then "plan.identity" else "plan.persisted.identity"),
                  [Arg ("id", To_String (Plan.Plan_Id))]) & LF);
            if Plan.Tasks.Is_Empty then
               Append (Result, Message ("plan.none") & LF);
            else
               for Spec of Plan.Tasks loop
                  Append
                    (Result,
                     To_String (Spec.Id) & "  [" & Improve.Model.Image (Spec.Task_Priority) & "] " &
                     To_String (Spec.Title) & LF & "  " & To_String (Spec.Acceptance) & LF);
               end loop;
            end if;
         end if;
         return To_String (Result);
      end;
   end Plan_Output;

   function Apply_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      State        : Improve.Storage.Store;
      Plan         : Improve.Model.Plan_Revision;
      Existing     : Improve.Storage.Publication_Vectors.Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector;
      Approved     : Boolean := False;
      Operation_Id : Natural := 0;
   begin
      Improve.Storage.Open (State, State_Path (Item), Writable => False);
      Plan := Improve.Storage.Load (State, To_String (Item.Target));
      Existing := Improve.Storage.Publications (State, To_String (Plan.Plan_Id));
      Approved := Improve.Storage.Is_Approved (State, To_String (Plan.Plan_Id), Plan.Revision);
      Improve.Storage.Close (State);
      if Item.Has_Task then
         if (for all Spec of Plan.Tasks => To_String (Spec.Id) /= To_String (Item.Task_Id)) then
            raise Argument_Error with "task does not belong to plan: " & To_String (Item.Task_Id);
         end if;
         Selected_Task_Ids.Append (Item.Task_Id);
      end if;
      if not Item.Dry_Run and then
        (To_String (Plan.Review_Status) = "pending" or else
         (for some Spec of Plan.Tasks => Spec.Requires_Review)) and then not Approved
      then
         raise Argument_Error with
           "plan revision requires approval; run improve plan approve " & To_String (Plan.Plan_Id);
      end if;
      declare
         Current_Source : constant String :=
           Improve.Source.Working_Fingerprint (To_String (Plan.Project.Path));
      begin
         if Current_Source /= To_String (Plan.Working_Source_Id) then
            raise Data_Error with
              "current project source differs from the assessment baseline; remeasure and refresh the plan";
         end if;
      end;
      declare
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path (Item, Settings));
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Latest  : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
         begin
            Require_Project_Identity (Plan.Project, Project);
            if Latest.Assessment.Run.Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Source_Id /= Plan.Baseline.Source_Id
            then
               raise Data_Error with "project source changed after planning; refresh the plan before publication";
            elsif Latest.Assessment.Run.Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Policy_Id /= Plan.Baseline.Policy_Id
            then
               raise Data_Error with
                 "quality policy changed after planning; replan before publication to preserve acceptance intent";
            end if;
         end;
         Improve.Source.Close (Quality);
      end;
      if not Item.Dry_Run then
         declare
            Preflight : constant Improve.Workflow.Publication_Result :=
              Improve.Workflow.Publish
                (To_String (Plan.Project.Path), Plan, To_String (Settings.Task_Kind), Existing,
                 Selected_Task_Ids => Selected_Task_Ids, Existing_Only => False, Dry_Run => True);
            pragma Unreferenced (Preflight);
            Task_Ids : Improve.Model.UString_Vectors.Vector;
         begin
            if Selected_Task_Ids.Is_Empty then
               for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
            else
               Task_Ids := Selected_Task_Ids;
            end if;
            Improve.Storage.Open (State, State_Path (Item), Writable => True);
            Operation_Id := Improve.Storage.Begin_Publication (State, Plan, Task_Ids);
            Improve.Storage.Close (State);
         end;
      end if;
      declare
         Published : constant Improve.Workflow.Publication_Result :=
           Improve.Workflow.Publish
             (To_String (Plan.Project.Path), Plan, To_String (Settings.Task_Kind), Existing,
              Selected_Task_Ids, False, Item.Dry_Run);
      begin
         if not Item.Dry_Run then
            declare Mappings : Improve.Storage.Publication_Vectors.Vector; begin
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.State, Plan.Revision));
               end loop;
               Improve.Storage.Open (State, State_Path (Item), Writable => True);
               Improve.Storage.Record_Publications (State, To_String (Plan.Plan_Id), Mappings);
               Improve.Storage.Complete_Publication (State, Positive (Operation_Id));
               Improve.Storage.Close (State);
            end;
         end if;
         if Item.Format = JSON_Format then
            return Improve.JSON.Publication (To_String (Plan.Plan_Id), Published, Item.Dry_Run);
         end if;
         declare Result : Unbounded_String; begin
            Append
              (Result,
               Improve.Presentation.Header
                 (Message ("apply.title", [Arg ("plan", To_String (Plan.Plan_Id))])) & LF);
            Append (Result, Message (if Item.Dry_Run then "apply.preview" else "apply.complete") & LF);
            for Value of Published.Tasks loop
               Append
                 (Result,
                  To_String (Value.Improve_Id) & " -> " &
                  (if Length (Value.Harness_Id) = 0 then "candidate" else To_String (Value.Harness_Id)) &
                  "  " & To_String (Value.State) & (if Value.Recovered then " (recovered)" else "") & LF);
            end loop;
            return To_String (Result);
         end;
      end;
   end Apply_Output;

   function One_Line (Text : String) return String is
      Result : String := Text;
   begin
      for Value of Result loop
         if Value in ASCII.HT | ASCII.LF | ASCII.CR then Value := ' '; end if;
      end loop;
      return Result;
   end One_Line;

   function Views_For
     (State : in out Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
      Current_Assessment : Natural := 0) return Improve.Tasks.View_Vectors.Vector is
     (Improve.Tasks.Build
        (Plan,
         Improve.Storage.Publications (State, To_String (Plan.Plan_Id)),
         Improve.Storage.Verifications (State, To_String (Plan.Plan_Id)),
         Current_Assessment));

   function Tasks_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      State      : Improve.Storage.Store;
      Project_Id : Natural := 0;
      Current_Assessment : Natural := 0;
      Filtered   : Improve.Tasks.View_Vectors.Vector;
      Filter     : constant String := (if Item.Has_Status then To_String (Item.Status_Filter) else "all");
      Found_Task : Boolean := not Item.Has_Task;
   begin
      if not Improve.Tasks.Valid_Filter (Filter) then
         raise Argument_Error with "invalid task status filter: " & Filter;
      end if;
      if Item.Has_Project then
         declare Quality : Improve.Source.Repository; begin
            Improve.Source.Open (Quality, Quality_Path (Item, Settings));
            declare
               Project : constant Improve.Model.Project_Reference :=
                 Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
               Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
            begin
               Project_Id := Project.Id;
               Current_Assessment := Selected.Baseline.Run_Id;
            end;
            Improve.Source.Close (Quality);
         end;
      end if;
      Improve.Storage.Open (State, State_Path (Item), Writable => False);
      if Item.Has_Task then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Storage.Load_Task (State, To_String (Item.Task_Id), Item.Revision);
            Plan_Views : constant Improve.Tasks.View_Vectors.Vector :=
              Views_For (State, Plan, Current_Assessment);
         begin
            if Project_Id /= 0 and then Plan.Project.Id /= Project_Id then
               raise Argument_Error with "task does not belong to selected project";
            end if;
            for View of Plan_Views loop
               if View.Improve_Id = Item.Task_Id then
                  Found_Task := True;
                  if Improve.Tasks.Matches (View, Filter) then Filtered.Append (View); end if;
               end if;
            end loop;
         end;
      else
         declare Summaries : constant Improve.Storage.Summary_Vectors.Vector :=
           Improve.Storage.List (State, Project_Id);
         begin
            if Summaries.Length > Ada.Containers.Count_Type (Settings.Maximum_Output_Items) then
               raise Data_Error with "task query exceeds output.maximum_output_items";
            end if;
            for Summary of Summaries loop
               declare
                  Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Storage.Load (State, To_String (Summary.Plan_Id));
                  Plan_Views : constant Improve.Tasks.View_Vectors.Vector :=
                    Views_For (State, Plan, Current_Assessment);
               begin
                  for View of Plan_Views loop
                     if Improve.Tasks.Matches (View, Filter) then Filtered.Append (View); end if;
                  end loop;
               end;
            end loop;
         end;
      end if;
      Improve.Storage.Close (State);
      if not Found_Task then raise Argument_Error with "unknown Improve task " & To_String (Item.Task_Id); end if;
      if Filtered.Length > Ada.Containers.Count_Type (Settings.Maximum_Output_Items) then
         raise Data_Error with "task query exceeds output.maximum_output_items";
      end if;
      Improve.Tasks.Sort (Filtered);
      if Item.Format = JSON_Format then return Improve.JSON.Tasks (Filtered, Filter); end if;
      declare Result : Unbounded_String; begin
         Append (Result, Improve.Presentation.Header (Message ("tasks.title")) & LF);
         if Filtered.Is_Empty then Append (Result, Message ("tasks.none") & LF);
         else
            Append
              (Result,
               Message ("label.id") & "  " & Message ("label.harness") & "  " & Message ("label.status") &
               "  " & Message ("label.title") & LF);
            for View of Filtered loop
               Append
                 (Result,
                  To_String (View.Improve_Id) & "  " &
                  (if Length (View.Harness_Id) = 0 then "-" else To_String (View.Harness_Id)) & "  " &
                  Improve.Tasks.Image (View.Status) & "  " & One_Line (To_String (View.Title)) & LF);
            end loop;
         end if;
         return To_String (Result);
      end;
   end Tasks_Output;

   function Status_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      State   : Improve.Storage.Store;
      Quality : Improve.Source.Repository;
      Values  : Improve.Tasks.Status_Vectors.Vector;
      Total_Items : Natural := 0;

      procedure Add_Project (Project : Improve.Model.Project_Reference; Latest_Run : Natural) is
         Summaries : constant Improve.Storage.Summary_Vectors.Vector :=
           Improve.Storage.List (State, Project);
         Value     : Improve.Tasks.Project_Status;
         Last_Plan : Improve.Model.Plan_Revision;
         Last_Views : Improve.Tasks.View_Vectors.Vector;
         Has_Plan  : Boolean := False;
      begin
         Value.Project_Id := Project.Id;
         Value.Project := Project.Name;
         Value.Latest_Run := Latest_Run;
         Value.Plan_Count := Natural (Summaries.Length);
         for Summary of Summaries loop
            declare
               Plan : constant Improve.Model.Plan_Revision :=
                 Improve.Storage.Load (State, To_String (Summary.Plan_Id));
               Plan_Views : constant Improve.Tasks.View_Vectors.Vector := Views_For (State, Plan, Latest_Run);
               Latest_Project_Run : Natural := 0;
               Latest_Plan_Run : Natural := 0;
            begin
               for Evidence of Improve.Storage.Verifications (State, To_String (Plan.Plan_Id)) loop
                  if Evidence.Plan_Revision = Plan.Revision and then
                    Evidence.Contract_Fingerprint = Plan.Fingerprint and then
                    Evidence.Scope = Improve.Storage.Project_Evaluation and then
                    Evidence.Assessment_Id >= Latest_Project_Run
                  then
                     Latest_Project_Run := Evidence.Assessment_Id;
                     Value.Project_Quality := Evidence.Outcome;
                     Value.Has_Project_Verification := True;
                     Value.Project_Verification_Run := Evidence.Assessment_Id;
                  elsif Evidence.Plan_Revision = Plan.Revision and then
                    Evidence.Contract_Fingerprint = Plan.Fingerprint and then
                    Evidence.Scope = Improve.Storage.Plan_Evaluation and then
                    Evidence.Assessment_Id >= Latest_Plan_Run
                  then
                     Latest_Plan_Run := Evidence.Assessment_Id;
                     Value.Plan_Quality := Evidence.Outcome;
                     Value.Has_Plan_Verification := True;
                     Value.Plan_Verification_Run := Evidence.Assessment_Id;
                  end if;
               end loop;
               Value.Tasks.Append_Vector (Plan_Views);
               Last_Plan := Plan;
               Last_Views := Plan_Views;
               Value.Baseline_Run := Plan.Baseline.Run_Id;
               Has_Plan := True;
               Total_Items := Total_Items + Natural (Plan_Views.Length);
            end;
         end loop;
         if Has_Plan then Value.Findings := Improve.Tasks.Findings (Last_Plan, Last_Views); end if;
         Improve.Tasks.Sort (Value.Tasks);
         Values.Append (Value);
      end Add_Project;

      procedure Add_Resolved_Project (Project : Improve.Model.Project_Reference) is
         Latest : Natural := 0;
      begin
         begin
            declare Selected : constant Improve.Source.Selection :=
              Improve.Source.Select_Assessment (Quality, Project);
            begin
               Latest := Selected.Baseline.Run_Id;
            end;
         exception
            when Dependency_Error => null;
         end;
         Add_Project (Project, Latest);
      end Add_Resolved_Project;
   begin
      Improve.Source.Open (Quality, Quality_Path (Item, Settings));
      Improve.Storage.Open (State, State_Path (Item), Writable => False);
      if Item.All_Projects then
         declare Projects : constant Ada_Quality.Reporting.Project_Vectors.Vector := Improve.Source.Projects (Quality);
         begin
            if Projects.Length > Ada.Containers.Count_Type (Settings.Maximum_Output_Items) then
               raise Data_Error with "status query exceeds output.maximum_output_items";
            end if;
            for Registered of Projects loop
               Add_Resolved_Project (Improve.Source.Resolve_Project (Quality, Number (Registered.Id)));
            end loop;
         end;
      else
         Add_Resolved_Project (Improve.Source.Resolve_Project (Quality, To_String (Item.Project)));
      end if;
      Improve.Storage.Close (State);
      Improve.Source.Close (Quality);
      if Total_Items > Settings.Maximum_Output_Items then
         raise Data_Error with "status query exceeds output.maximum_output_items";
      end if;
      if Item.Format = JSON_Format then return Improve.JSON.Status (Values); end if;
      declare Result : Unbounded_String; begin
         for Value of Values loop
            if Length (Result) > 0 then Append (Result, LF); end if;
            Append
              (Result,
               Improve.Presentation.Header
                 (Message ("status.title", [Arg ("project", To_String (Value.Project))])) & LF &
               Message ("status.baseline", [Arg ("run", Number (Value.Baseline_Run))]) & LF &
               Message ("status.latest", [Arg ("run", Number (Value.Latest_Run))]) & LF &
               Message ("status.plans", [Arg ("count", Number (Value.Plan_Count))]) & LF &
               Message ("status.tasks", [Arg ("count", Number (Natural (Value.Tasks.Length)))]) & LF &
               "Plan quality: " &
               (if Value.Has_Plan_Verification and then Value.Plan_Verification_Run = Value.Latest_Run
                then Improve.Model.Image (Value.Plan_Quality)
                else "unverified") & LF &
               "Project quality: " &
               (if Value.Has_Project_Verification and then Value.Project_Verification_Run = Value.Latest_Run
                then Improve.Model.Image (Value.Project_Quality)
                else "unverified") & LF);
            if Value.Has_Plan_Verification then
               Append
                 (Result,
                  "Last plan verification assessment: " & Number (Value.Plan_Verification_Run) & LF);
               if Value.Plan_Verification_Run /= Value.Latest_Run then
                  Append (Result, "Previous plan result: " & Improve.Model.Image (Value.Plan_Quality) & LF);
               end if;
            end if;
            if Value.Has_Project_Verification then
               Append
                 (Result,
                  "Last project verification assessment: " & Number (Value.Project_Verification_Run) & LF);
               if Value.Project_Verification_Run /= Value.Latest_Run then
                  Append (Result, "Previous project result: " & Improve.Model.Image (Value.Project_Quality) & LF);
               end if;
            end if;
            for Status in Improve.Tasks.Operational_Status loop
               declare Count : Natural := 0; begin
                  for View of Value.Tasks loop
                     if View.Status = Status then Count := Count + 1; end if;
                  end loop;
                  if Count > 0 then
                     Append
                       (Result,
                        "  " & Improve.Tasks.Image (Status) & " " & Number (Count) & LF);
                  end if;
               end;
            end loop;
            Append
              (Result,
               Message ("status.findings") & LF &
               "  resolved " & Number (Value.Findings.Resolved) & LF &
               "  outstanding " & Number (Value.Findings.Outstanding) & LF &
               "  not_measurable " & Number (Value.Findings.Not_Measurable) & LF &
               "  regressed " & Number (Value.Findings.Regressed) & LF &
               "  superseded " & Number (Value.Findings.Superseded) & LF);
         end loop;
         return To_String (Result);
      end;
   end Status_Output;

   function Recover_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Report : constant Improve.Recovery.Recovery_Report :=
        Improve.Recovery.Recover
          (State_Path (Item), To_String (Settings.Task_Kind), Settings.Maximum_Recovery_Operations);
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Recovery (Report); end if;
      return
        Improve.Presentation.Header (Message ("recover.title")) & LF &
        Message
          ("recover.complete",
           [Arg ("operations", Number (Report.Operations_Recovered)),
            Arg ("tasks", Number (Report.Tasks_Recovered))]) & LF;
   end Recover_Output;

   function Verify_Output
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Negative : out Boolean;
      Command  : String := "verify") return String is
      State : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
      Previously_Verified : Improve.Model.UString_Vectors.Vector;
   begin
      Improve.Storage.Open (State, State_Path (Item), Writable => False);
      if Item.Has_Task then
         Plan := Improve.Storage.Load_Task (State, To_String (Item.Task_Id), Item.Revision);
      else
         declare
            Quality : Improve.Source.Repository;
            Project : Improve.Model.Project_Reference;
         begin
            Improve.Source.Open (Quality, Quality_Path (Item, Settings));
            Project := Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
            Improve.Source.Close (Quality);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan :=
                 (if Item.Has_Revision then
                     Improve.Storage.Load
                       (State, To_String (Values.Last_Element.Plan_Id), Positive (Item.Revision))
                  else Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id)));
            end;
         end;
      end if;
      Improve.Storage.Close (State);
      declare
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path (Item, Settings));
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Current : constant Improve.Source.Selection :=
              Improve.Source.Select_Assessment (Quality, Project, Item.Run_Id);
         begin
            Require_Project_Identity (Plan.Project, Project);
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path (Item), Writable => False);
            for Record_Value of Improve.Storage.Verifications (State, To_String (Plan.Plan_Id)) loop
               for Spec of Plan.Tasks loop
                  if Record_Value.Scope = Improve.Storage.Task_Evaluation and then
                    Record_Value.Task_Id = Spec.Id and then
                    To_String (Record_Value.Contract_Fingerprint) =
                      Improve.Verification.Contract_Fingerprint (Spec) and then
                    Record_Value.Assessment_Id < Current.Baseline.Run_Id and then
                    Record_Value.Outcome = Improve.Model.Verified and then
                    not Previously_Verified.Contains (Record_Value.Task_Id)
                  then
                     Previously_Verified.Append (Record_Value.Task_Id);
                     exit;
                  end if;
               end loop;
            end loop;
            Improve.Storage.Close (State);
            declare
               Report : constant Improve.Verification.Report :=
                 Improve.Verification.Evaluate
                   (Plan, Current, Settings, (if Item.Has_Task then To_String (Item.Task_Id) else ""),
                    Previously_Verified);
               Records : Improve.Storage.Verification_Vectors.Vector;
            begin
               for Result of Report.Tasks loop
                  for Spec of Plan.Tasks loop
                     if Spec.Id = Result.Task_Id then
                        Records.Append
                          (Improve.Storage.Verification_Record'
                             (Scope           => Improve.Storage.Task_Evaluation,
                              Task_Id         => Result.Task_Id,
                              Plan_Revision   => Plan.Revision,
                              Contract_Fingerprint => To_Unbounded_String
                                (Improve.Verification.Contract_Fingerprint (Spec)),
                              Assessment_Id   => Report.Verification_Run,
                              Outcome         => Result.Outcome,
                              Comparable      => Report.Comparable,
                              Explanation     => Result.Explanation));
                        exit;
                     end if;
                  end loop;
               end loop;
               if not Item.Has_Task then
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope         => Improve.Storage.Plan_Evaluation,
                        Task_Id       => Null_Unbounded_String,
                        Plan_Revision => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id => Report.Verification_Run,
                        Outcome       => Report.Plan_Outcome,
                        Comparable    => Report.Comparable,
                        Explanation   => Report.Explanation));
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope         => Improve.Storage.Project_Evaluation,
                        Task_Id       => Null_Unbounded_String,
                        Plan_Revision => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id => Report.Verification_Run,
                        Outcome       => Report.Project_Outcome,
                        Comparable    => Report.Comparable,
                        Explanation   => Report.Explanation));
               end if;
               Improve.Storage.Open (State, State_Path (Item), Writable => True);
               Improve.Storage.Record_Verification (State, To_String (Plan.Plan_Id), Records);
               Improve.Storage.Close (State);
               Negative := Report.Outcome /= Improve.Model.Verified;
               if Item.Format = JSON_Format then return Improve.JSON.Verification (Report, Command); end if;
               declare Output : Unbounded_String; begin
                  Append
                    (Output,
                     Improve.Presentation.Header
                       (Message
                          ((if Command = "refresh" then "refresh.title" else "verify.title"),
                           [Arg ("plan", To_String (Plan.Plan_Id))])) & LF);
                  Append (Output, "Outcome: " & Improve.Model.Image (Report.Outcome) & LF);
                  for Result of Report.Tasks loop
                     Append (Output, To_String (Result.Task_Id) & "  " & Improve.Model.Image (Result.Outcome) & LF);
                  end loop;
                  return To_String (Output);
               end;
            end;
         end;
      end;
   end Verify_Output;

   function Refresh_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      State       : Improve.Storage.Store;
      Plan        : Improve.Model.Plan_Revision;
      Publications : Improve.Storage.Publication_Vectors.Vector;
      Ignored     : Boolean;
   begin
      declare Quality : Improve.Source.Repository; begin
         Improve.Source.Open (Quality, Quality_Path (Item, Settings));
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
         begin
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path (Item), Writable => False);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan := Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id));
               Require_Project_Identity (Plan.Project, Project);
               Publications := Improve.Storage.Publications (State, To_String (Plan.Plan_Id));
            end;
            Improve.Storage.Close (State);
         end;
      end;
      if not Publications.Is_Empty then
         declare
            Published  : Improve.Workflow.Published_Vectors.Vector;
            Reconciled : Improve.Workflow.Published_Vectors.Vector;
            Updates    : Improve.Storage.Publication_Vectors.Vector;
         begin
            for Value of Publications loop
               Published.Append
                 (Improve.Workflow.Published_Task'
                    (Improve_Id => Value.Improve_Task_Id,
                     Harness_Id => Value.Harness_Task_Id,
                     Origin     => Value.Origin,
                     State      => Value.State,
                     Recovered  => True));
            end loop;
            Reconciled := Improve.Workflow.Reconcile (To_String (Plan.Project.Path), Published);
            for Value of Reconciled loop
               Updates.Append
                 (Improve.Storage.Publication_Record'
                    (Improve_Task_Id => Value.Improve_Id,
                     Harness_Task_Id => Value.Harness_Id,
                     Origin          => Value.Origin,
                     State           => Value.State,
                     Plan_Revision   => Plan.Revision));
            end loop;
            Improve.Storage.Open (State, State_Path (Item), Writable => True);
            Improve.Storage.Update_Publication_States (State, Updates);
            Improve.Storage.Close (State);
         end;
      end if;
      return Verify_Output (Item, Settings, Ignored, Command => "refresh");
   end Refresh_Output;

   function Dispatch (Item : Invocation; Negative : out Boolean) return String is
      Plain : Unbounded_String;
      Settings : constant Improve.Config.Settings := Improve.Config.Load (Configuration_Path);
   begin
      Negative := False;
      Improve.Presentation.Configure (Item.Format, Item.Color);
      case Item.Command is
         when Help_Command => Plain := To_Unbounded_String (Help_Text);
         when Version_Command =>
            Plain := To_Unbounded_String (Message ("help.version", [Arg ("version", Version)]) & LF);
         when Config_Command =>
            if Item.Has_Target and then To_String (Item.Target) = "validate" then
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

   function Diagnostic (Text : String) return String is
     (Message ("error.prefix", [Arg ("message", Text)]) & LF);

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Item : Invocation;
      Negative : Boolean := False;
   begin
      Item := Parse (Arguments);
      declare Output : constant String := Dispatch (Item, Negative); begin
         return
           ((if Negative then Negative_Exit else Success_Exit),
            To_Unbounded_String (Output), Null_Unbounded_String);
      end;
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

