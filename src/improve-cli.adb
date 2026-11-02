with Ada.Command_Line;
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
with Improve.Source;
with Improve.Storage;
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
   use type Improve.Model.Quality_Outcome;

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
      if Item.Plan_Action = Show_Plan then
         declare State : Improve.Storage.Store; begin
            Improve.Storage.Open (State, State_Path (Item), Writable => False);
            declare Plan : constant Improve.Model.Plan_Revision :=
              Improve.Storage.Load (State, To_String (Item.Target));
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
              Improve.Storage.List (State, Project.Id);
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
      State : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
   begin
      Improve.Storage.Open (State, State_Path (Item), Writable => False);
      Plan := Improve.Storage.Load (State, To_String (Item.Target));
      Improve.Storage.Close (State);
      if Item.Has_Task then
         declare
            Selected : Improve.Model.Task_Vectors.Vector;
         begin
            for Spec of Plan.Tasks loop
               if To_String (Spec.Id) = To_String (Item.Task_Id) then Selected.Append (Spec); end if;
            end loop;
            if Selected.Is_Empty then
               raise Argument_Error with "task does not belong to plan: " & To_String (Item.Task_Id);
            end if;
            Plan.Tasks := Selected;
         end;
      end if;
      declare
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path (Item, Settings));
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Latest  : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Quality, Project);
         begin
            if Latest.Assessment.Run.Id > Plan.Baseline.Run_Id and then
              Latest.Baseline.Source_Id /= Plan.Baseline.Source_Id
            then
               raise Data_Error with "project source changed after planning; refresh the plan before publication";
            end if;
         end;
         Improve.Source.Close (Quality);
      end;
      declare
         Published : constant Improve.Workflow.Publication_Result :=
           Improve.Workflow.Publish
             (To_String (Plan.Project.Path), Plan, To_String (Settings.Task_Kind), Item.Dry_Run);
      begin
         if not Item.Dry_Run then
            declare Mappings : Improve.Storage.Publication_Vectors.Vector; begin
               for Value of Published.Tasks loop
                  Mappings.Append
                    (Improve.Storage.Publication_Record'
                       (Value.Improve_Id, Value.Harness_Id, Value.Origin, Value.State));
               end loop;
               Improve.Storage.Open (State, State_Path (Item), Writable => True);
               Improve.Storage.Record_Publications (State, To_String (Plan.Plan_Id), Mappings);
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
         declare Found : Boolean := False; begin
            for Summary of Improve.Storage.List (State) loop
               declare Candidate : constant Improve.Model.Plan_Revision :=
                 Improve.Storage.Load (State, To_String (Summary.Plan_Id));
               begin
                  for Spec of Candidate.Tasks loop
                     if To_String (Spec.Id) = To_String (Item.Task_Id) then
                        Plan := Candidate;
                        Found := True;
                        exit;
                     end if;
                  end loop;
               end;
               exit when Found;
            end loop;
            if not Found then raise Argument_Error with "unknown Improve task " & To_String (Item.Task_Id); end if;
         end;
      else
         declare
            Quality : Improve.Source.Repository;
            Project : Improve.Model.Project_Reference;
         begin
            Improve.Source.Open (Quality, Quality_Path (Item, Settings));
            Project := Improve.Source.Resolve_Project (Quality, To_String (Item.Project));
            Improve.Source.Close (Quality);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project.Id);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan := Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id));
            end;
         end;
      end if;
      for Record_Value of Improve.Storage.Verifications (State, To_String (Plan.Plan_Id)) loop
         if Record_Value.Outcome = Improve.Model.Verified and then
           not Previously_Verified.Contains (Record_Value.Task_Id)
         then
            Previously_Verified.Append (Record_Value.Task_Id);
         end if;
      end loop;
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
            Report : constant Improve.Verification.Report :=
              Improve.Verification.Evaluate
                (Plan, Current, Settings, (if Item.Has_Task then To_String (Item.Task_Id) else ""),
                 Previously_Verified);
            Records : Improve.Storage.Verification_Vectors.Vector;
         begin
            Improve.Source.Close (Quality);
            for Result of Report.Tasks loop
               Records.Append
                 (Improve.Storage.Verification_Record'
                    (Result.Task_Id, Report.Verification_Run, Result.Outcome,
                     Report.Comparable, Result.Explanation));
            end loop;
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
              Improve.Storage.List (State, Project.Id);
            begin
               if Values.Is_Empty then raise Argument_Error with "project has no stored remediation plan"; end if;
               Plan := Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id));
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
                     State           => Value.State));
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
         when Verify_Command => return Verify_Output (Item, Settings, Negative);
         when Refresh_Command => return Refresh_Output (Item, Settings);
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

