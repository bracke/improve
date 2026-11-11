with Ada.Command_Line;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Ada_Quality.Reporting;
with Ada_Quality.Types;
with Improve.CLI.Parsing;
with Improve.Findings;
with Improve.JSON;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Planning;
with Improve.Operations.Publication;
with Improve.Operations.Reconciliation;
with Improve.Operations.Verification;
with Improve.Presentation;
with Improve.Recovery;
with Improve.Source;
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
   use type Improve.Model.Quality_Outcome;
   use type Improve.Tasks.Operational_Status;

   LF : constant Character := Character'Val (10);

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
                     Improve.Presentation.Safe_Text (To_String (Value.Path)) & LF);
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
             (Selected, Improve.Config.Quality_Severity (Settings.Minimum_Severity),
              Settings.Allow_Investigation_Tasks);
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
                        Ada_Quality.Types.Severity'Image (Value.Level) & "  " &
                        Improve.Presentation.Safe_Text (Location) & "  " &
                        Improve.Presentation.Safe_Text (To_String (Value.Message)) & LF);
                  end;
               end loop;
            end if;
         end if;
         Improve.Source.Close (Store);
         return To_String (Result);
      end;
   end Findings_Output;

   function Plan_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
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
               Improve.Presentation.Safe_Text (To_String (Spec.Title)) & LF & "  " &
               Improve.Presentation.Safe_Text (To_String (Spec.Acceptance)) & LF);
         end loop;
         return To_String (Result);
      end Stored_Plan_Terminal;
   begin
      if Item.Plan_Action = Approve_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Approve
                (State_Path (Item), To_String (Item.Target),
                 Improve.Operations.Storage_Read_Limits (Settings));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Approval (Plan); end if;
            return
              Message
                ("plan.approved",
                 [Arg ("id", To_String (Plan.Plan_Id)), Arg ("revision", Number (Plan.Revision))]) & LF;
         end;
      elsif Item.Plan_Action = Show_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Load
                (State_Path (Item), To_String (Item.Target),
                 (if Item.Has_Revision then Item.Revision else 0),
                 Improve.Operations.Storage_Read_Limits (Settings));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan (Plan, Dry_Run => False); end if;
            return Stored_Plan_Terminal (Plan);
         end;
      elsif Item.Plan_Action = List_Plans then
         declare
            Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Operations.Planning.List
                (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
                 Settings.Maximum_Output_Items);
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plans (Values); end if;
            declare Result : Unbounded_String; begin
               Append (Result, Improve.Presentation.Header (Message ("plan.list.title")) & LF);
               if Values.Is_Empty then Append (Result, Message ("plan.list.none") & LF); end if;
               for Value of Values loop
                  Append
                    (Result,
                     Message
                       ("plan.list.item",
                        [Arg ("id", To_String (Value.Plan_Id)), Arg ("revision", Number (Value.Revision)),
                         Arg ("tasks", Number (Value.Task_Count)), Arg ("run", Number (Value.Run_Id))]) & LF);
               end loop;
               return To_String (Result);
            end;
         end;
      end if;
      declare
         Executed : constant Improve.Operations.Planning.Generation_Result :=
           Improve.Operations.Planning.Generate
             (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
              Item.Run_Id, Settings, Item.Dry_Run);
         Plan   : constant Improve.Model.Plan_Revision := Executed.Plan;
         Result : Unbounded_String;
      begin
         if Item.Format = JSON_Format then
            Result := To_Unbounded_String (Improve.JSON.Plan (Plan, Item.Dry_Run));
         else
            Append
              (Result,
               Improve.Presentation.Header
                 (Message
                    ("plan.title",
                     [Arg ("project", To_String (Plan.Project.Name)),
                      Arg ("run", Number (Plan.Baseline.Run_Id))])) & LF);
            Append
              (Result,
               Message
                 ((if Item.Dry_Run then "plan.dry_run"
                   elsif Executed.Existing then "plan.existing"
                   else "plan.stored")) & LF);
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
                     Improve.Presentation.Safe_Text (To_String (Spec.Title)) & LF & "  " &
                     Improve.Presentation.Safe_Text (To_String (Spec.Acceptance)) & LF);
               end loop;
            end if;
         end if;
         return To_String (Result);
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
           Limits           => Improve.Operations.Storage_Read_Limits (Settings));
   begin
      if Item.Format = JSON_Format then
         return Improve.JSON.Publication
           (To_String (Executed.Plan.Plan_Id), Executed.Published, Item.Dry_Run);
      end if;
      declare Result : Unbounded_String; begin
         Append
           (Result,
            Improve.Presentation.Header
              (Message ("apply.title", [Arg ("plan", To_String (Executed.Plan.Plan_Id))])) & LF);
         Append (Result, Message (if Item.Dry_Run then "apply.preview" else "apply.complete") & LF);
         for Value of Executed.Published.Tasks loop
            Append
              (Result,
               To_String (Value.Improve_Id) & " -> " &
               (if Length (Value.Harness_Id) = 0 then "candidate" else To_String (Value.Harness_Id)) &
               "  " & To_String (Value.State) & (if Value.Recovered then " (recovered)" else "") & LF);
         end loop;
         return To_String (Result);
      end;
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
           Limits           => Improve.Operations.Storage_Read_Limits (Settings));
   begin
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
                  Improve.Tasks.Image (View.Status) & "  " &
                  Improve.Presentation.Safe_Text (To_String (View.Title)) & LF);
            end loop;
         end if;
         return To_String (Result);
      end;
   end Tasks_Output;

   function Status_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Values : constant Improve.Tasks.Status_Vectors.Vector :=
        Improve.Operations.Inspection.Status
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.All_Projects then "" else To_String (Item.Project)),
           All_Projects     => Item.All_Projects,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Limits           => Improve.Operations.Storage_Read_Limits (Settings));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Status (Values); end if;
      declare Result : Unbounded_String; begin
         for Value of Values loop
            if Length (Result) > 0 then Append (Result, LF); end if;
            Append
              (Result,
               Improve.Presentation.Header
                 (Message
                    ("status.title",
                     [Arg ("project", Improve.Presentation.Safe_Text (To_String (Value.Project)))])) & LF &
               Message ("status.baseline", [Arg ("run", Number (Value.Baseline_Run))]) & LF &
               Message ("status.latest", [Arg ("run", Number (Value.Latest_Run))]) & LF &
               Message ("status.plans", [Arg ("count", Number (Value.Plan_Count))]) & LF &
               Message ("status.tasks", [Arg ("count", Number (Natural (Value.Tasks.Length)))]) & LF &
               Message
                 ("status.plan_quality",
                  [Arg
                     ("outcome",
                      (if Value.Has_Plan_Verification and then Value.Plan_Verification_Run = Value.Latest_Run
                       then Improve.Model.Image (Value.Plan_Quality)
                       else Improve.Model.Image (Improve.Model.Unverified)))]) & LF &
               Message
                 ("status.project_quality",
                  [Arg
                     ("outcome",
                      (if Value.Has_Project_Verification and then Value.Project_Verification_Run = Value.Latest_Run
                       then Improve.Model.Image (Value.Project_Quality)
                       else Improve.Model.Image (Improve.Model.Unverified)))]) & LF);
            if Value.Has_Plan_Verification then
               Append
                 (Result,
                  Message
                    ("status.last_plan_verification",
                     [Arg ("run", Number (Value.Plan_Verification_Run))]) & LF);
               if Value.Plan_Verification_Run /= Value.Latest_Run then
                  Append
                    (Result,
                     Message
                       ("status.previous_plan_result",
                        [Arg ("outcome", Improve.Model.Image (Value.Plan_Quality))]) & LF);
               end if;
            end if;
            if Value.Has_Project_Verification then
               Append
                 (Result,
                  Message
                    ("status.last_project_verification",
                     [Arg ("run", Number (Value.Project_Verification_Run))]) & LF);
               if Value.Project_Verification_Run /= Value.Latest_Run then
                  Append
                    (Result,
                     Message
                       ("status.previous_project_result",
                        [Arg ("outcome", Improve.Model.Image (Value.Project_Quality))]) & LF);
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
                        Message
                          ("status.count",
                           [Arg ("status", Improve.Tasks.Image (Status)), Arg ("count", Number (Count))]) & LF);
                  end if;
               end;
            end loop;
            Append
              (Result,
               Message ("status.findings") & LF &
               Message ("status.count", [Arg ("status", "resolved"),
                 Arg ("count", Number (Value.Findings.Resolved))]) & LF &
               Message ("status.count", [Arg ("status", "outstanding"),
                 Arg ("count", Number (Value.Findings.Outstanding))]) & LF &
               Message ("status.count", [Arg ("status", "not_measurable"),
                 Arg ("count", Number (Value.Findings.Not_Measurable))]) & LF &
               Message ("status.count", [Arg ("status", "regressed"),
                 Arg ("count", Number (Value.Findings.Regressed))]) & LF &
               Message ("status.count", [Arg ("status", "superseded"),
                 Arg ("count", Number (Value.Findings.Superseded))]) & LF &
               Message ("status.count", [Arg ("status", "previously_resolved"),
                 Arg ("count", Number (Value.Findings.Previously_Resolved))]) & LF &
               Message ("status.count", [Arg ("status", "unverified"),
                 Arg ("count", Number (Value.Findings.Unverified))]) & LF);
         end loop;
         return To_String (Result);
      end;
   end Status_Output;

   function Recover_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Report : constant Improve.Recovery.Recovery_Report :=
        Improve.Recovery.Recover
          (State_Path (Item), To_String (Settings.Task_Kind), Settings.Maximum_Recovery_Operations,
           Improve.Operations.Storage_Read_Limits (Settings));
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
      if Item.Format = JSON_Format then
         return Improve.JSON.Verification (Executed.Report, Command);
      end if;
      declare Output : Unbounded_String; begin
         Append
           (Output,
            Improve.Presentation.Header
              (Message
                 ((if Command = "refresh" then "refresh.title" else "verify.title"),
                  [Arg ("plan", To_String (Executed.Plan.Plan_Id))])) & LF);
         Append
           (Output,
            Message
              ("verify.outcome", [Arg ("outcome", Improve.Model.Image (Executed.Report.Outcome))]) & LF);
         for Result of Executed.Report.Tasks loop
            Append (Output, To_String (Result.Task_Id) & "  " & Improve.Model.Image (Result.Outcome) & LF);
         end loop;
         return To_String (Output);
      end;
   end Verify_Output;

   function Refresh_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Ignored     : Boolean;
   begin
      Improve.Operations.Reconciliation.Run
        (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
         Improve.Operations.Storage_Read_Limits (Settings));
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
     (Message ("error.prefix", [Arg ("message", Improve.Presentation.Safe_Text (Text))]) & LF);

   function Execute (Arguments : String_Vectors.Vector) return Outcome is
      Item : Invocation;
      Negative : Boolean := False;
   begin
      Item := Parse (Arguments);
      declare Settings : constant Improve.Config.Settings := Improve.Config.Load (Configuration_Path); begin
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

