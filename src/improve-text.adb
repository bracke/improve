with Ada.Strings.Fixed;
with Messages.Arguments;
with Messages.Result;
with Messages.Runtime;

package body Improve.Text is
   use Ada.Strings.Unbounded;
   use type Messages.Result.Render_Status;
   use type Messages.Runtime.Load_Status;

   LF : constant Character := Character'Val (10);
   Catalog : constant String :=
     "default_locale=en" & LF &
     "en.error.prefix = improve: {message}" & LF &
     "en.error.hint = run improve help for usage" & LF &
     "en.error.internal = internal error: {message}" & LF &
     "en.error.output = cannot write output: {message}" & LF &
     "en.help.usage = Usage: improve <command> [options]" & LF &
     "en.help.commands = Commands:" & LF &
     "en.help.cmd.projects = List available projects" & LF &
     "en.help.cmd.findings = List findings eligible for remediation" & LF &
     "en.help.cmd.plan = Generate or inspect remediation plans" & LF &
     "en.help.cmd.apply = Publish a plan to the harness" & LF &
     "en.help.cmd.tasks = List and inspect remediation tasks" & LF &
     "en.help.cmd.status = Show remediation progress" & LF &
     "en.help.cmd.refresh = Reconcile against current measurements" & LF &
     "en.help.cmd.verify = Verify remediation results" & LF &
     "en.help.cmd.recover = Recover interrupted operations" & LF &
     "en.help.cmd.config = Show and validate configuration" & LF &
     "en.help.cmd.help = Display help" & LF &
     "en.help.cmd.version = Display version" & LF &
     "en.help.options = Global options:" & LF &
     "en.help.opt.database = Ada Quality database" & LF &
     "en.help.opt.state = Improve state database" & LF &
     "en.help.opt.project = Project identity or unique name" & LF &
     "en.help.opt.format = Output format: terminal or json" & LF &
     "en.help.opt.color = Color policy: auto, always, or never" & LF &
     "en.help.opt.verbose = Include operational detail" & LF &
     "en.help.opt.quiet = Suppress nonessential terminal output" & LF &
     "en.help.opt.help = Display help" & LF &
     "en.help.exit = Exit codes: 0 success, 1 unresolved verification, 2 invalid input, 3 unavailable," &
       " 4 failure." & LF &
     "en.help.version = improve {version}" & LF &
     "en.config.valid = Configuration is valid." & LF &
     "en.config.title = Effective Improve configuration" & LF &
     "en.projects.title = Registered Ada Quality projects" & LF &
     "en.projects.none = No active projects are registered." & LF &
     "en.findings.title = Remediation findings for {project}, assessment {run}" & LF &
     "en.findings.none = No eligible findings or unavailable evidence." & LF &
     "en.plan.title = Remediation plan for {project}, assessment {run}" & LF &
     "en.plan.dry_run = Preview only; this plan has not been stored." & LF &
     "en.plan.identity = Deterministic draft identity: {id}" & LF &
     "en.plan.none = No remediation tasks are required." & LF &
     "en.plan.persistence.pending = persistent plans become available in implementation phase 4; use --dry-run" & LF &
     "en.label.id = ID" & LF &
     "en.label.project = Project" & LF &
     "en.label.enabled = Enabled" & LF &
     "en.label.path = Path" & LF &
     "en.label.indicator = Indicator" & LF &
     "en.label.severity = Severity" & LF &
     "en.label.location = Location" & LF &
     "en.label.message = Message" & LF &
     "en.phase.pending = command {command} is not available before its implementation phase" & LF;

   Runtime : Messages.Runtime.Instance;
   Loaded  : Boolean := False;
   Valid   : Boolean := False;

   procedure Ensure_Loaded is
      Result : Messages.Runtime.Load_Result;
   begin
      if not Loaded then
         Messages.Runtime.Load_Text (Runtime, "improve", Catalog, Result);
         Valid := Result.Status = Messages.Runtime.Loaded;
         Loaded := True;
      end if;
   end Ensure_Loaded;

   function Arg (Name, Value : String) return Argument is
     ((To_Unbounded_String (Name), To_Unbounded_String (Value)));

   function Message (Key : String; Args : Argument_List := No_Arguments) return String is
      Values : Messages.Arguments.Arguments;
   begin
      Ensure_Loaded;
      if not Valid or else Ada.Strings.Fixed.Index (Catalog, LF & "en." & Key & " = ") = 0 then
         raise Data_Error with "missing message " & Key;
      end if;
      for Item of Args loop
         Messages.Arguments.Set (Values, To_String (Item.Name), To_String (Item.Value));
      end loop;
      declare
         Rendered : constant Messages.Result.Render_Result := Messages.Runtime.Render (Runtime, "en", Key, Values);
      begin
         if Rendered.Status /= Messages.Result.Success then
            raise Data_Error with "cannot render message " & Key;
         end if;
         return Messages.Result.Output_Text (Rendered.Text);
      end;
   end Message;

   function Catalog_Is_Valid return Boolean is
   begin
      Ensure_Loaded;
      return Valid;
   end Catalog_Is_Valid;
end Improve.Text;
