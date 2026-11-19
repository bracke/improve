with Ada.Command_Line;
with Ada.Containers;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Text_IO.Text_Streams;
with Improve.CLI.Parsing;
with Improve.CLI_Assets;
with Improve.Audit_Artifacts;
with Improve.JSON;
with Improve.Inspection_Filters;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Audit;
with Improve.Operations.Diagnostics;
with Improve.Operations.Planning;
with Improve.Operations.Publication;
with Improve.Operations.Reconciliation;
with Improve.Operations.Recovery;
with Improve.Operations.Verification;
with Improve.Presentation;
with Improve.Results;
with Improve.State;
with Improve.Tasks;
with Improve.Text;
with Project_Tools.Files;

package body Improve.CLI is
   use Ada.Strings.Unbounded;
   use Improve.Config;
   use Improve.Text;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Results.Diagnostic_Status;
   LF : constant Character := Character'Val (10);
   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
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
         when Audit_Command => "audit",
         when Apply_Command => "apply", when Tasks_Command => "tasks", when Status_Command => "status",
         when Refresh_Command => "refresh", when Verify_Command => "verify", when Recover_Command => "recover",
         when Doctor_Command => "doctor", when Config_Command => "config", when Completion_Command => "completion",
         when Manpage_Command => "manpage", when Help_Command => "help", when Version_Command => "version");

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
      Line ("plan", "help.cmd.plan"); Line ("audit", "help.cmd.audit");
      Line ("apply", "help.cmd.apply"); Line ("tasks", "help.cmd.tasks");
      Line ("status", "help.cmd.status"); Line ("refresh", "help.cmd.refresh");
      Line ("verify", "help.cmd.verify"); Line ("recover", "help.cmd.recover");
      Line ("doctor", "help.cmd.doctor"); Line ("config", "help.cmd.config");
      Line ("completion", "help.cmd.completion"); Line ("manpage", "help.cmd.manpage");
      Line ("help", "help.cmd.help"); Line ("version", "help.cmd.version");
      Append (Result, LF & Message ("help.options") & LF);
      Line ("--config PATH", "help.opt.config", 36);
      Line ("--database PATH", "help.opt.database", 36); Line ("--state PATH", "help.opt.state", 36);
      Line ("--project ID|NAME", "help.opt.project", 36);
      Line ("--format terminal|json|markdown|dot", "help.opt.format", 36);
      Line ("--color auto|always|never", "help.opt.color", 36);
      Line ("--progress auto|always|never", "help.opt.progress", 36);
      Line ("--run ID", "help.opt.run", 36); Line ("--revision NUMBER", "help.opt.revision", 36);
      Line ("--against-revision NUMBER", "help.opt.against_revision", 36);
      Line ("--task ID", "help.opt.task", 36);
      Line ("--status STATUS", "help.opt.status", 36); Line ("--dry-run", "help.opt.dry_run", 36);
      Line ("--indicator ID", "help.opt.indicator", 36); Line ("--severity LEVEL", "help.opt.severity", 36);
      Line ("--path TEXT", "help.opt.path", 36);
      Line ("--limit N / --cursor N", "help.opt.path", 36); Line ("--signing-key FILE", "help.opt.path", 36);
      Line ("--agent-model NAME", "help.opt.agent_model", 36);
      Line ("--agent-model-path FILE", "help.opt.agent_model_path", 36);
      Line ("--agent-model-sha256 HEX", "help.opt.agent_model_sha256", 36);
      Line ("--no-agent", "help.opt.no_agent", 36);
      Line ("--release", "help.opt.path", 36); Line ("--all", "help.opt.all", 36);
      Line ("--verbose", "help.opt.verbose", 36); Line ("--quiet", "help.opt.quiet", 36);
      Line ("--help", "help.opt.help", 36);
      Append (Result, LF & Message ("help.exit") & LF);
      return To_String (Result);
   end Help_Text;

   function Configuration_Path (Item : Invocation) return String is
     (if Item.Has_Config then To_String (Item.Config)
      elsif Project_Tools.Files.File_Exists ("config/improve.toml") then "config/improve.toml"
      else "");

   function Quality_Path (Item : Invocation; Settings : Improve.Config.Settings) return String is
     (if Item.Has_Database then To_String (Item.Database) else To_String (Settings.Quality_Database));

   function State_Path (Item : Invocation) return String is
     (if Item.Has_State then To_String (Item.State) else ".improve.db");
   function Render_Terminal
     (Item     : Invocation;
      Renderer : not null access function return String) return String is
      Style : Improve.Presentation.Styling_Scope :=
        Improve.Presentation.Configure (Item.Format, Item.Color);
      pragma Unreferenced (Style);
   begin
      declare Rendered : constant String := Renderer.all; begin
         if Item.Format = Markdown_Format then
            return "# Improve " & Name (Item.Command) & LF & LF & "```text" & LF & Rendered & "```" & LF;
         end if;
         return Rendered;
      end;
   end Render_Terminal;

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
         declare
            Limit : constant Natural :=
              (if Item.Has_Limit then Item.Limit else Settings.Maximum_Output_Items);
         begin
            if Natural (Inspected.Values.Length) > Limit then
               Next := To_Unbounded_String (Number (Item.Cursor + Limit));
               Inspected.Values.Delete_Last (Inspected.Values.Length - Ada.Containers.Count_Type (Limit));
            end if;
         end;
      end if;
      if Item.Format = JSON_Format then
         return Improve.JSON.Findings (Inspected, To_String (Next));
      end if;
      return Render_Terminal (Item, Render'Access);
   end Findings_Output;

   function Plan_Output
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Provider : access Improve.Refinement.Adapter'Class) return String is
   begin
      if Item.Plan_Action = Diff_Plan then
         declare
            Compared : constant Improve.Results.Plan_Comparison :=
              Improve.Operations.Planning.Compare
                (State_Path (Item), To_String (Item.Target), Positive (Item.Against_Revision),
                 Positive (Item.Revision), Improve.Operations.Storage_Limits (Settings));
            function Render return String is (Improve.Presentation.Plan_Comparison (Compared, False));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Comparison (Compared, False); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = Explain_Plan then
         declare
            Compared : constant Improve.Results.Plan_Comparison :=
              Improve.Operations.Planning.Explain
                (State_Path (Item), To_String (Item.Target), Item.Revision,
                 Improve.Operations.Storage_Limits (Settings));
            function Render return String is (Improve.Presentation.Plan_Comparison (Compared, True));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Comparison (Compared, True); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = Approve_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Approve
                (State_Path (Item), To_String (Item.Target),
                 Improve.Operations.Storage_Limits (Settings));

            function Render return String is
              (Improve.Presentation.Plan_Approval (Plan));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Approval (Plan); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action in Show_Plan | Graph_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Load
                (State_Path (Item), To_String (Item.Target),
                 (if Item.Has_Revision then Item.Revision else 0),
                 Improve.Operations.Storage_Limits (Settings));

            function Render return String is
              (if Item.Plan_Action = Graph_Plan then Improve.Presentation.Plan_Graph (Plan)
               else Improve.Presentation.Plan (Plan));
         begin
            Require_Output_Items (Plan.Tasks.Length, Settings.Maximum_Output_Items, "plan task output");
            if Item.Plan_Action = Graph_Plan and then Item.Format = JSON_Format then
               return Improve.JSON.Plan_Graph (Plan);
            elsif Item.Format = JSON_Format then
               return Improve.JSON.Plan (Plan, Dry_Run => False);
            end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = List_Plans then
         declare
            Values : Improve.State.Summary_Vectors.Vector :=
              Improve.Operations.Planning.List
                (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
                 Settings.Maximum_Output_Items, Improve.Operations.Storage_Limits (Settings),
                 Improve.Operations.Quality_Load_Limits (Settings),
                 Improve.Config.Evidence_Limits_Of (Settings));

            Next : Unbounded_String;
            function Render return String is
              (Improve.Presentation.Plans (Values) &
               (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
         begin
            if Item.Has_Limit or else Item.Has_Cursor then
               if Item.Cursor >= Natural (Values.Length) then Values.Clear;
               elsif Item.Cursor > 0 then Values.Delete_First (Ada.Containers.Count_Type (Item.Cursor)); end if;
               declare Limit : constant Natural :=
                 (if Item.Has_Limit then Item.Limit else Settings.Maximum_Output_Items);
               begin
                  if Natural (Values.Length) > Limit then
                     Next := To_Unbounded_String (Number (Item.Cursor + Limit));
                     Values.Delete_Last (Values.Length - Ada.Containers.Count_Type (Limit));
                  end if;
               end;
            end if;
            if Item.Format = JSON_Format then return Improve.JSON.Plans (Values, To_String (Next)); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      end if;
      if Settings.Agent_Enabled and then Provider = null then
         raise Dependency_Error with
           "planning.agent_enabled requires the improve-model-runner executable";
      end if;
      if Settings.Agent_Enabled then
         declare
            Identity : constant Improve.Refinement.Adapter_Provenance :=
              Improve.Refinement.Provenance (Provider.all);
            Digest : constant String := To_String (Identity.Model_SHA256);
            Expected : constant String := To_String (Settings.Agent_Model_SHA256);
         begin
            if Expected /= "" then
               if Digest'Length /= 64 or else Digest = [1 .. 64 => '0'] or else
                 (for some C of Digest => C not in '0' .. '9' | 'a' .. 'f')
               then
                  raise Dependency_Error with "configured model runtime did not open successfully";
               elsif Digest /= Expected then
                  raise Dependency_Error with "configured model SHA-256 does not match the opened model";
               end if;
            end if;
         end;
      end if;
      declare
         Executed : constant Improve.Operations.Planning.Generation_Result :=
           Improve.Operations.Planning.Generate
             (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
              Item.Run_Id, Settings, Item.Dry_Run,
              Provider => (if Settings.Agent_Enabled then Provider else null));
         Plan   : constant Improve.Model.Plan_Revision := Executed.Plan;

         function Render return String is
           (Improve.Presentation.Generated_Plan (Plan, Item.Dry_Run, Executed.Existing));
      begin
         if Item.Format = JSON_Format then
            return Improve.JSON.Plan (Plan, Item.Dry_Run);
         end if;
         return Render_Terminal (Item, Render'Access);
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

   function Audit_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
   begin
      if Item.Audit_Verify then
         declare Text : constant String := Project_Tools.Files.Read_Raw_File (To_String (Item.Target)); begin
            if Text = "" then raise Dependency_Error with "audit document is unavailable"; end if;
            Improve.Audit_Artifacts.Verify (Text);
            return
              (if Item.Format = JSON_Format then Improve.JSON.Text ("audit verify", "integrity", "valid")
               else "Audit bundle integrity is valid." & LF);
         end;
      end if;
      declare
         Bundle : Improve.Results.Audit_Bundle :=
           Improve.Operations.Audit.Run
             (State_Path (Item), To_String (Item.Target), Item.Revision,
              Settings.Maximum_Output_Items, Improve.Operations.Storage_Limits (Settings));
         Next : Unbounded_String;
         function Render return String is
           (Improve.Presentation.Audit (Bundle) &
            (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
      begin
      if Item.Has_Limit or else Item.Has_Cursor then
         declare Limit : constant Natural := (if Item.Has_Limit then Item.Limit else Settings.Maximum_Output_Items);
         begin
            if Item.Cursor >= Natural (Bundle.History.Publications.Length) then Bundle.History.Publications.Clear;
            elsif Item.Cursor > 0 then
               Bundle.History.Publications.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
            end if;
            if Item.Cursor >= Natural (Bundle.History.Verifications.Length) then Bundle.History.Verifications.Clear;
            elsif Item.Cursor > 0 then
               Bundle.History.Verifications.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
            end if;
            if Natural (Bundle.History.Publications.Length) > Limit or else
              Natural (Bundle.History.Verifications.Length) > Limit
            then
               Next := To_Unbounded_String (Number (Item.Cursor + Limit));
            end if;
            if Natural (Bundle.History.Publications.Length) > Limit then
               Bundle.History.Publications.Delete_Last
                 (Bundle.History.Publications.Length - Ada.Containers.Count_Type (Limit));
            end if;
            if Natural (Bundle.History.Verifications.Length) > Limit then
               Bundle.History.Verifications.Delete_Last
                 (Bundle.History.Verifications.Length - Ada.Containers.Count_Type (Limit));
            end if;
         end;
      end if;
      if Item.Format = JSON_Format then
         declare
            Seed : constant String :=
              (if Item.Has_Signing_Key then
                 Project_Tools.Files.Read_Raw_File (To_String (Item.Signing_Key)) else "");
            Clean_Seed : constant String :=
              (if Seed'Length > 0 and then Seed (Seed'Last) = LF then Seed (Seed'First .. Seed'Last - 1) else Seed);
         begin
            if Item.Has_Signing_Key and then Clean_Seed = "" then
               raise Dependency_Error with "audit signing key is unavailable or empty"; end if;
            return Improve.JSON.Audit (Bundle, To_String (Next), Clean_Seed);
         end;
      end if;
      return Render_Terminal (Item, Render'Access);
      end;
   end Audit_Output;

   function Tasks_Output
     (Item                        : Invocation;
      Settings                    : Improve.Config.Settings;
      Quality_Database_Configured : Boolean) return String is
      Filter     : constant String := (if Item.Has_Status then To_String (Item.Status_Filter) else "all");
      Filtered   : Improve.Tasks.View_Vectors.Vector :=
        Improve.Operations.Inspection.Tasks
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.Has_Project then To_String (Item.Project) else ""),
           Task_Id          => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Revision         => Item.Revision,
           Filter           => Filter,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Require_Quality  =>
             Item.Has_Database or else Quality_Database_Configured,
           Limits           => Improve.Operations.Storage_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));

      Next : Unbounded_String;
      function Render return String is
        (Improve.Presentation.Tasks (Filtered) &
         (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
   begin
      if Item.Has_Limit or else Item.Has_Cursor then
         if Item.Cursor >= Natural (Filtered.Length) then Filtered.Clear;
         elsif Item.Cursor > 0 then Filtered.Delete_First (Ada.Containers.Count_Type (Item.Cursor)); end if;
         declare Limit : constant Natural := (if Item.Has_Limit then Item.Limit else Settings.Maximum_Output_Items);
         begin
            if Natural (Filtered.Length) > Limit then
               Next := To_Unbounded_String (Number (Item.Cursor + Limit));
               Filtered.Delete_Last (Filtered.Length - Ada.Containers.Count_Type (Limit));
            end if;
         end;
      end if;
      if Item.Format = JSON_Format then return Improve.JSON.Tasks (Filtered, Filter, To_String (Next)); end if;
      return Render_Terminal (Item, Render'Access);
   end Tasks_Output;

   function Status_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Values : constant Improve.Tasks.Status_Vectors.Vector :=
        Improve.Operations.Inspection.Status
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.All_Projects then "" else To_String (Item.Project)),
           All_Projects     => Item.All_Projects,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Limits           => Improve.Operations.Storage_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));

      function Render return String is
        (Improve.Presentation.Status (Values));
   begin
      if Item.Format = JSON_Format then return Improve.JSON.Status (Values); end if;
      return Render_Terminal (Item, Render'Access);
   end Status_Output;

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
         when Plan_Command => return Plan_Output (Item, Settings, Provider);
         when Audit_Command => return Audit_Output (Item, Settings);
         when Apply_Command => return Apply_Output (Item, Settings);
         when Tasks_Command =>
            return Tasks_Output (Item, Settings, Configuration.Quality_Database_Configured);
         when Status_Command => return Status_Output (Item, Settings);
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

   function Configuration_For
     (Arguments : String_Vectors.Vector) return Improve.Config.Loaded_Configuration is
      Item : constant Invocation := Parse (Arguments);
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

