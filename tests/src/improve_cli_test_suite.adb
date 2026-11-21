with Ada.Exceptions;
with Ada.Environment_Variables;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve.CLI;
with Improve.Config;
with Improve.Presentation;
with Improve.Presentation.Testing;
with Improve.Results;
with Improve.State;
with Improve.Tasks;
with Project_Tools.Files;
with Project_Tools.Processes;
with Project_Tools.Test_Fixtures;
with Terminal_Styles;
package body Improve_CLI_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI.Plan_Operation;
   use type Improve.CLI.Progress_Mode;
   use type Improve.Config.Color_Mode;
   use type Improve.Config.Output_Format;
   use type Terminal_Styles.Color_Policy;
   type Test_Id is
     (Parse_Plan, Reject_Duplicate, Reject_Conflict, Reject_Missing_Project, Reject_Command_Option,
      JSON_Disables_Color, Terminal_Text_Sanitized, Styling_Concurrency, Help_Smoke, Version_Smoke,
      Quiet_Smoke, Verbose_Smoke, Config_Smoke, Extended_Parse, Assets_Smoke, Invalid_Smoke);
   type Case_Test (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Case_Test;

   overriding procedure Run_Test (Item : in out Case_Test);
   overriding function Name (Item : Case_Test) return AUnit.Message_String is
     (AUnit.Format ("IMP_" & Test_Id'Image (Item.Id)));

   function Args (Text : String) return Improve.CLI.String_Vectors.Vector is
      Result : Improve.CLI.String_Vectors.Vector;
      Start  : Positive := Text'First;
   begin
      if Text = "" then
         return Result;
      end if;
      for Index in Text'Range loop
         if Text (Index) = '|' then
            Result.Append (Text (Start .. Index - 1));
            Start := Index + 1;
         end if;
      end loop;
      Result.Append (Text (Start .. Text'Last));
      return Result;
   end Args;
   procedure Must_Reject (Text, Expected : String) is
      Rejected : Boolean := False;
   begin
      begin
         declare
            Item : constant Improve.CLI.Invocation := Improve.CLI.Parse (Args (Text));
            pragma Unreferenced (Item);
         begin
            null;
         end;
      exception
         when Error : Improve.Argument_Error =>
            Rejected := Ada.Strings.Fixed.Index (Ada.Exceptions.Exception_Message (Error), Expected) > 0;
      end;
      Assert (Rejected, "expected rejection containing '" & Expected & "'");
   end Must_Reject;
   function Shell_Syntax_Valid (Shell, Script : String) return Boolean is
      Path : constant String := Project_Tools.Processes.Locate_Command (Shell);
      Required : constant Boolean :=
        Ada.Environment_Variables.Value ("IMPROVE_REQUIRE_COMPLETION_SHELLS", "") = "1";
   begin
      if Path = "" then
         return not Required;
      end if;
      declare
         Probe : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture_Command
             (Path,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("-n"),
                  Project_Tools.Processes.Argument ("-c"),
                  Project_Tools.Processes.Argument (Script)]),
              Err_To_Out => True);
      begin
         return Probe.Status = 0;
      end;
   end Shell_Syntax_Valid;
   function Fish_Completion_Valid (Script : String) return Boolean is
      Path : constant String := Project_Tools.Processes.Locate_Command ("fish");
      Required : constant Boolean :=
        Ada.Environment_Variables.Value ("IMPROVE_REQUIRE_COMPLETION_SHELLS", "") = "1";
   begin
      if Path = "" then
         return not Required;
      end if;
      declare
         Probe : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture_Command
             (Path,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("-c"),
                  Project_Tools.Processes.Argument
                    (Script & ASCII.LF &
                     "for item in (complete -C 'improve --format '); echo format:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve audit '); echo audit:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve config '); echo config:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve help '); echo help:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve config --s'); echo config-option:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve audit verify --s'); echo audit-option:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve plan show PLAN-1 --l'); " &
                     "echo plan-option:$item; end" & ASCII.LF &
                     "for item in (complete -C 'improve --project completion '); echo collision:$item; end")]),
              Err_To_Out => True);
         Output : constant String := To_String (Probe.Output);
      begin
         return Probe.Status = 0 and then
           Ada.Strings.Fixed.Index (Output, "format:terminal") > 0 and then
           Ada.Strings.Fixed.Index (Output, "format:json") > 0 and then
           Ada.Strings.Fixed.Index (Output, "format:markdown") > 0 and then
           Ada.Strings.Fixed.Index (Output, "format:dot") > 0 and then
           Ada.Strings.Fixed.Index (Output, "audit:verify") > 0 and then
           Ada.Strings.Fixed.Index (Output, "config:validate") > 0 and then
           Ada.Strings.Fixed.Index (Output, "config:explain") > 0 and then
           Ada.Strings.Fixed.Index (Output, "help:projects") > 0 and then
           Ada.Strings.Fixed.Index (Output, "config-option:--state") > 0 and then
           Ada.Strings.Fixed.Index (Output, "config-option:--signing-key") = 0 and then
           Ada.Strings.Fixed.Index (Output, "audit-option:--signing-key") = 0 and then
           Ada.Strings.Fixed.Index (Output, "plan-option:--limit") = 0 and then
           Ada.Strings.Fixed.Index (Output, "collision:projects") > 0 and then
           Ada.Strings.Fixed.Index (Output, "collision:bash") = 0;
      end;
   end Fish_Completion_Valid;

   function Zsh_Completion_Valid (Script : String) return Boolean is
      Path : constant String := Project_Tools.Processes.Locate_Command ("zsh");
      Required : constant Boolean :=
        Ada.Environment_Variables.Value ("IMPROVE_REQUIRE_COMPLETION_SHELLS", "") = "1";
   begin
      if Path = "" then
         return not Required;
      end if;
      declare
         Root : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-zsh-completion");
      begin
         begin
            Project_Tools.Files.Write_Raw_File (Project_Tools.Files.Join (Root, "_improve"), Script);
            declare
               Probe : constant Project_Tools.Processes.Captured_Process :=
                 Project_Tools.Processes.Capture_Command
                   (Path,
                    Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("-f"),
                        Project_Tools.Processes.Argument ("-c"),
                        Project_Tools.Processes.Argument
                          ("zmodload zsh/zpty || exit 1" & ASCII.LF &
                           "zpty improve_probe env PS1=IMPROVE_READY " & Path & " -f || exit 1" & ASCII.LF &
                           "zpty -r improve_probe chunk '*IMPROVE_READY*' || exit 1" & ASCII.LF &
                           "zpty -w improve_probe 'fpath=(" & Root & " $fpath); autoload -Uz compinit; " &
                           "compinit -i -D; setopt AUTO_LIST LIST_AMBIGUOUS'" & ASCII.LF &
                           "zpty -r improve_probe chunk '*IMPROVE_READY*' || exit 1" & ASCII.LF &
                           "zpty -w improve_probe $'improve plan \t\t\n'" & ASCII.LF &
                           "zpty -r improve_probe chunk '*IMPROVE_READY*' || exit 1" & ASCII.LF &
                           "print -r -- ""$chunk""" & ASCII.LF &
                           "zpty -w improve_probe $'improve config --s\t\t\n'" & ASCII.LF &
                           "zpty -r improve_probe chunk '*IMPROVE_READY*' || exit 1" & ASCII.LF &
                           "print -r -- ""$chunk""" & ASCII.LF &
                           "zpty -w improve_probe $'improve audit verify --s\t\t\n'" & ASCII.LF &
                           "zpty -r improve_probe chunk '*IMPROVE_READY*' || exit 1" & ASCII.LF &
                           "print -r -- ""$chunk""" & ASCII.LF &
                           "zpty -w improve_probe exit")]),
                    Err_To_Out => True);
               Output : constant String := To_String (Probe.Output);
               Valid  : constant Boolean :=
                 Probe.Status = 0 and then
                 Ada.Strings.Fixed.Index (Output, "list") > 0 and then
                 Ada.Strings.Fixed.Index (Output, "approve") > 0 and then
                 Ada.Strings.Fixed.Index (Output, "graph") > 0 and then
                 Ada.Strings.Fixed.Index (Output, "--state") > 0 and then
                 Ada.Strings.Fixed.Index (Output, "--signing-key") = 0;
            begin
               Project_Tools.Test_Fixtures.Cleanup (Root);
               return Valid;
            end;
         exception
            when others =>
               Project_Tools.Test_Fixtures.Cleanup (Root);
               return False;
         end;
      end;
   end Zsh_Completion_Valid;

   procedure Check_Styling_Concurrency is
      protected type Start_Gate is
         procedure Open;
         entry Wait;
      private
         Ready : Boolean := False;
      end Start_Gate;

      protected body Start_Gate is
         procedure Open is
         begin
            Ready := True;
         end Open;

         entry Wait when Ready is
         begin
            null;
         end Wait;
      end Start_Gate;

      protected type Completion is
         procedure Set (Value : Boolean; Detail : String := "");
         entry Wait (Value : out Boolean; Detail : out Unbounded_String);
      private
         Done    : Boolean := False;
         Success : Boolean := False;
         Message : Unbounded_String;
      end Completion;

      protected body Completion is
         procedure Set (Value : Boolean; Detail : String := "") is
         begin
            Success := Value;
            Message := To_Unbounded_String (Detail);
            Done := True;
         end Set;

         entry Wait (Value : out Boolean; Detail : out Unbounded_String) when Done is
         begin
            Value := Success;
            Detail := Message;
         end Wait;
      end Completion;

      procedure Exercise
        (Arguments            : String;
         Should_Wait_For_Lock : Boolean;
         Label                : String) is
         Start    : Start_Gate;
         Finished : Completion;
         Completed  : Boolean := False;
         Successful : Boolean := False;
         Failure    : Unbounded_String;

         task Worker;

         task body Worker is
            Result : Improve.CLI.Outcome;
         begin
            Start.Wait;
            Result := Improve.CLI.Execute (Args (Arguments));
            Finished.Set (Result.Exit_Code = 0);
         exception
            when Error : others =>
               Finished.Set (False, Ada.Exceptions.Exception_Information (Error));
         end Worker;

         procedure Await_Worker is
         begin
            Completed := False;
            select
               Finished.Wait (Successful, Failure);
               Completed := True;
            or
               delay 2.0;
            end select;
            if not Completed then
               abort Worker;
            end if;
            Assert (Completed, Label & " worker did not complete");
         end Await_Worker;

         Previous : constant Terminal_Styles.Color_Policy :=
           Terminal_Styles.Current_Color_Policy;
      begin
         declare
            Style : Improve.Presentation.Styling_Scope :=
              Improve.Presentation.Configure
                (Improve.Config.Terminal_Format, Improve.Config.Color_Always);
            pragma Unreferenced (Style);
         begin
            Start.Open;
            if Should_Wait_For_Lock then
               declare
                  use type Ada.Real_Time.Time;
                  Deadline : constant Ada.Real_Time.Time :=
                    Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (2.0);
               begin
                  while Improve.Presentation.Testing.Waiting_Tasks = 0
                    and then Ada.Real_Time.Clock < Deadline
                  loop
                     delay 0.001;
                  end loop;
                  if Improve.Presentation.Testing.Waiting_Tasks = 0 then
                     abort Worker;
                  end if;
                  Assert
                    (Improve.Presentation.Testing.Waiting_Tasks > 0,
                     Label & " did not reach the terminal-style lock");
               end;
            else
               Await_Worker;
            end if;
            Assert
              (Terminal_Styles.Current_Color_Policy = Terminal_Styles.Color_Always,
               Label & " changed another task's active terminal policy");
         end;
         if Should_Wait_For_Lock then
            Await_Worker;
         end if;
         Assert
           (Successful,
            Label & " execution failed" &
              (if Length (Failure) = 0 then "" else ": " & To_String (Failure)));
         Assert
           (Terminal_Styles.Current_Color_Policy = Previous,
            Label & " did not restore the terminal policy");
      end Exercise;
   begin
      Exercise ("version|--format|json", False, "JSON rendering");
      Exercise ("config|--format|terminal|--color|never", True, "terminal rendering");
   end Check_Styling_Concurrency;
   overriding procedure Run_Test (Item : in out Case_Test) is
   begin
      case Item.Id is
         when Parse_Plan =>
            declare
               Parsed : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse
                   (Args ("--config|custom.toml|--database|q.db|plan|--project|demo|--run=42|--dry-run"));
            begin
               Assert
                 (Parsed.Command = Improve.CLI.Plan_Command and then
                  Parsed.Plan_Action = Improve.CLI.Create_Plan and then Parsed.Run_Id = 42 and then
                  Parsed.Dry_Run and then Parsed.Has_Config and then
                  To_String (Parsed.Config) = "custom.toml" and then To_String (Parsed.Project) = "demo",
                  "plan options were not parsed");
            end;
         when Reject_Duplicate =>
            Must_Reject ("projects|--format|json|--format|terminal", "more than once");
         when Reject_Conflict =>
            Must_Reject ("projects|--verbose|--quiet", "mutually exclusive");
         when Reject_Missing_Project =>
            Must_Reject ("findings", "requires --project");
         when Reject_Command_Option =>
            Must_Reject ("projects|--run|1", "not accepted");
         when JSON_Disables_Color =>
            declare
               Parsed : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("projects|--format|json|--color|always"));
            begin
               Assert (Parsed.Color = Improve.Config.Color_Never, "JSON did not force color off");
            end;
         when Terminal_Text_Sanitized =>
            declare
               Unsafe : constant String := "before" & Character'Val (27) & "[2J" & ASCII.LF & "after";
               Safe   : constant String := Improve.Presentation.Safe_Text (Unsafe);
               Unicode_Unsafe : constant String :=
                 "left" & Character'Val (16#C2#) & Character'Val (16#9B#) &
                 Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#AE#) & "right";
               Unicode_Safe : constant String := Improve.Presentation.Safe_Text (Unicode_Unsafe);
               Invalid_UTF8_Safe : constant String :=
                 Improve.Presentation.Safe_Text ("raw" & Character'Val (16#9B#) & "control");
               Publications : constant Improve.Results.Publication_Result := (others => <>);
               Recovery     : constant Improve.Results.Recovery_Result :=
                 (Operations_Recovered => 1, Tasks_Recovered => 2);
               Verification : constant Improve.Results.Verification_Report :=
                 (Plan_Id          => To_Unbounded_String ("PLAN-000001"),
                  Baseline_Run     => 1,
                  Verification_Run => 2,
                  others           => <>);
            begin
               Assert
                 (Ada.Strings.Fixed.Index (Safe, Character'Val (27) & "[2J") = 0 and then
                  Ada.Strings.Fixed.Index (Safe, ASCII.LF & "after") = 0,
                  "terminal sanitizer retained control characters");
               Assert
                 (Ada.Strings.Fixed.Index (Unicode_Safe, String'(1 => Character'Val (16#9B#))) = 0 and then
                  Ada.Strings.Fixed.Index (Unicode_Safe, String'(1 => Character'Val (16#AE#))) = 0,
                  "terminal sanitizer retained Unicode control characters");
               Assert
                 (Ada.Strings.Fixed.Index
                    (Invalid_UTF8_Safe, String'(1 => Character'Val (16#9B#))) = 0,
                  "terminal sanitizer retained an invalid encoded control byte");
               Assert
                 (Improve.Presentation.Projects (Improve.Results.Project_Vectors.Empty_Vector)'Length > 0
                  and then
                  Improve.Presentation.Plans (Improve.State.Summary_Vectors.Empty_Vector)'Length > 0 and then
                  Improve.Presentation.Tasks (Improve.Tasks.View_Vectors.Empty_Vector)'Length > 0 and then
                  Improve.Presentation.Status (Improve.Tasks.Status_Vectors.Empty_Vector) = "" and then
                  Improve.Presentation.Publication ("PLAN-000001", Publications, True)'Length > 0 and then
                  Improve.Presentation.Recovery (Recovery)'Length > 0 and then
                  Improve.Presentation.Verification ("PLAN-000001", Verification, "refresh")'Length > 0,
                  "terminal empty-state rendering failed");
            end;
         when Styling_Concurrency =>
            Check_Styling_Concurrency;
         when Help_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("help"));
               Broken_Config : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("help|--config|missing-improve-config.toml"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then Broken_Config.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), "Usage:") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), "Pagination limit and cursor") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), "Signing key file") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Result.Output), "Validate the pin-free release candidate") > 0 and then
                  Ada.Strings.Fixed.Index
                    (To_String (Result.Output), "terminal, json, markdown, or dot") > 0,
                  "help depended on operational configuration");
            end;
         when Version_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--format|json"));
               Broken_Config : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("version|--config|missing-improve-config.toml"));
            begin
               Assert
                 (Result.Exit_Code = 0 and then Broken_Config.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), """schema_version"":2") > 0,
                  "version output depended on operational configuration or was not versioned");
            end;
         when Quiet_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--quiet")); begin
               Assert (Result.Exit_Code = 0 and then Length (Result.Output) = 0, "quiet output was not suppressed");
            end;
         when Verbose_Smoke =>
            declare Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("version|--verbose")); begin
               Assert
                 (Result.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Result.Output), "command version") > 0,
                  "verbose output omitted operational context");
            end;
         when Config_Smoke =>
            declare
               Config_Path : constant String :=
                 (if Project_Tools.Files.File_Exists ("config/improve.toml")
                  then "config/improve.toml" else "../config/improve.toml");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("config|validate|--config|" & Config_Path));
               Missing : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("config|validate|--config|missing-improve-config.toml"));
               Explained : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("config|explain|--config|" & Config_Path));
            begin
               Assert
                 (Result.Exit_Code = 0 and then Missing.Exit_Code = Improve.CLI.Argument_Exit and then
                  Ada.Strings.Fixed.Index (To_String (Explained.Output), "source:") > 0,
                  "configuration validation did not honor its explicit source");
            end;
         when Extended_Parse =>
            declare
               Diff : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse
                   (Args ("plan|diff|PLAN-000001|--against-revision|1|--revision|2|--format|markdown"));
               Findings : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse
                   (Args ("findings|--project|demo|--indicator|SEC-01|--severity|critical|--path|src"));
               Doctor : constant Improve.CLI.Invocation := Improve.CLI.Parse (Args ("doctor|--project|demo"));
               Audit : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("audit|PLAN-000001|--revision|2"));
               Graph : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("plan|graph|PLAN-000001|--format|dot"));
               Page : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("tasks|--project|demo|--limit|25|--cursor|50"));
               Release : constant Improve.CLI.Invocation := Improve.CLI.Parse (Args ("doctor|--release"));
               Agent : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse
                   (Args
                      ("plan|--project|demo|--agent-model|fixture|--agent-model-path|fixture.gguf|" &
                       "--agent-model-sha256|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|" &
                       "--progress|always"));
               Agent_Config : constant Improve.Config.Loaded_Configuration :=
                 Improve.CLI.Configuration_For
                   (Args ("version|--agent-model|fixture|--agent-model-path|fixture.gguf"));
               Disabled_Config : constant Improve.Config.Loaded_Configuration :=
                 Improve.CLI.Configuration_For (Args ("version|--no-agent"));
               Verify_Audit : constant Improve.CLI.Invocation :=
                 Improve.CLI.Parse (Args ("audit|verify|bundle.json|--verification-key|release.pub"));
            begin
               Assert
                 (Diff.Plan_Action = Improve.CLI.Diff_Plan and then Diff.Against_Revision = 1 and then
                  Diff.Revision = 2 and then Diff.Format = Improve.Config.Markdown_Format and then
                  Findings.Has_Indicator and then Findings.Has_Severity and then Findings.Has_Path and then
                  Doctor.Command = Improve.CLI.Doctor_Command and then
                  Audit.Command = Improve.CLI.Audit_Command and then
                  Audit.Revision = 2 and then Graph.Plan_Action = Improve.CLI.Graph_Plan and then
                  Graph.Format = Improve.Config.DOT_Format and then Page.Limit = 25 and then Page.Cursor = 50 and then
                  Release.Release_Check and then Verify_Audit.Audit_Verify and then
                  Verify_Audit.Has_Verification_Key and then
                  Agent.Has_Agent_Model and then Agent.Has_Agent_Model_Path and then
                  Agent.Has_Agent_Model_SHA256 and then Agent.Has_Progress and then
                  Agent.Progress = Improve.CLI.Progress_Always and then Agent_Config.Values.Agent_Enabled and then
                  To_String (Agent_Config.Values.Agent_Model) = "fixture" and then
                  not Disabled_Config.Values.Agent_Enabled,
                  "extended inspection and diagnostic options were not parsed");
               Must_Reject ("plan|diff|PLAN-000001|--revision|2", "requires --against-revision");
               Must_Reject ("tasks|--task|IMP-1|--severity|high", "accepted only");
               Must_Reject ("projects|--limit|2", "pagination");
               Must_Reject ("plan|--no-agent|--agent-model|fixture", "cannot be combined");
               Must_Reject ("plan|--progress|sometimes", "invalid --progress");
               Must_Reject ("plan|--quiet|--progress|always", "mutually exclusive");
               Must_Reject ("audit|PLAN-1|--verification-key|release.pub", "audit verify");
               Must_Reject ("config|show validate", "unexpected argument");
               Must_Reject ("completion|bash zsh", "unexpected argument");
               Must_Reject ("--format|=|json|version", "invalid --format");
            end;
         when Assets_Smoke =>
            declare
               Root_Prefix : constant String :=
                 (if Project_Tools.Files.File_Exists ("completions/improve.bash") then "" else "../");
               Completion : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("completion|bash"));
               Zsh        : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("completion|zsh"));
               Fish       : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("completion|fish"));
               Manpage    : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("manpage"));
               Markdown   : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("version|--format|markdown"));
               Bash_Text  : constant String := To_String (Completion.Output);
               Zsh_Text   : constant String := To_String (Zsh.Output);
               Fish_Text  : constant String := To_String (Fish.Output);
               Zsh_Syntax_Valid : constant Boolean := Shell_Syntax_Valid ("zsh", Zsh_Text);
               Fish_Syntax_Valid : constant Boolean := Shell_Syntax_Valid ("fish", Fish_Text);
               Zsh_Behavior_Valid : constant Boolean := Zsh_Completion_Valid (Zsh_Text);
               Fish_Behavior_Valid : constant Boolean := Fish_Completion_Valid (Fish_Text);
               Bash_Path  : constant String := Project_Tools.Processes.Locate_Command ("bash");
               Probe      : constant Project_Tools.Processes.Captured_Process :=
                 Project_Tools.Processes.Capture_Command
                   (Bash_Path,
                    Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("-c"),
                        Project_Tools.Processes.Argument
                          (Bash_Text & ASCII.LF &
                           "COMP_WORDS=(improve --format json plan ''); COMP_CWORD=4; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'plan:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve findings ''); COMP_CWORD=2; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'findings:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve --project completion ''); COMP_CWORD=3; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'collision:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve --format=j); COMP_CWORD=1; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'inline:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve --format = j); COMP_CWORD=3; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'split:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve config --s); COMP_CWORD=2; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do " &
                           "printf 'config-option:%s\n' ""$item""; done" & ASCII.LF &
                           "COMP_WORDS=(improve config --severity ''); COMP_CWORD=3; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'config-value:%s\n' ""$item""; done" &
                           ASCII.LF &
                           "COMP_WORDS=(improve audit verify --s); COMP_CWORD=3; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'audit-option:%s\n' ""$item""; done" &
                           ASCII.LF &
                           "COMP_WORDS=(improve plan show PLAN-1 --l); COMP_CWORD=4; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'plan-option:%s\n' ""$item""; done" &
                           ASCII.LF &
                           "compopt() { printf 'compopt:%s\n' ""$*""; }" & ASCII.LF &
                           "compgen() { printf '%s\n' 'file with space'; }" & ASCII.LF &
                           "COMP_WORDS=(improve --config ''); COMP_CWORD=2; _improve_complete" & ASCII.LF &
                           "for item in ""${COMPREPLY[@]}""; do printf 'file:%s\n' ""$item""; done")]),
                    Err_To_Out => True);
            begin
               Assert
                 (Completion.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Completion.Output), "complete -F") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Zsh.Output), "#compdef") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Fish.Output), "complete -c") > 0 and then
                  Manpage.Exit_Code = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Manpage.Output), ".TH IMPROVE") > 0 and then
                  To_String (Completion.Output) =
                    Project_Tools.Files.Read_Raw_File (Root_Prefix & "completions/improve.bash") and then
                  To_String (Zsh.Output) =
                    Project_Tools.Files.Read_Raw_File (Root_Prefix & "completions/_improve") and then
                  To_String (Fish.Output) =
                    Project_Tools.Files.Read_Raw_File (Root_Prefix & "completions/improve.fish") and then
                  To_String (Manpage.Output) =
                    Project_Tools.Files.Read_Raw_File (Root_Prefix & "docs/improve.1") and then
                  Ada.Strings.Fixed.Index (Zsh_Text, "--against-revision") > 0 and then
                  Ada.Strings.Fixed.Index (Fish_Text, "-l against-revision") > 0 and then
                  Ada.Strings.Fixed.Index (Zsh_Text, "--dry-run") > 0 and then
                  Ada.Strings.Fixed.Index (Fish_Text, "-l dry-run") > 0 and then
                  Zsh_Syntax_Valid and then Fish_Syntax_Valid and then
                  Zsh_Behavior_Valid and then Fish_Behavior_Valid and then
                  Ada.Strings.Fixed.Index (To_String (Markdown.Output), "# Improve version") = 1,
                  "generated CLI assets drifted from committed artifacts or Markdown output is invalid");
               Assert
                 (Bash_Path /= "" and then Probe.Status = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "plan:list") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "findings:list") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "collision:projects") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "collision:bash") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "inline:--format=json") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "split:json") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "compopt:-o filenames") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "file:file with space") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "config-option:--state") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "config-option:--signing-key") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "config-value:critical") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "audit-option:--signing-key") = 0 and then
                  Ada.Strings.Fixed.Index (To_String (Probe.Output), "plan-option:--limit") = 0,
                  "Bash completion did not locate an option-displaced command or leaked plan operations: " &
                  To_String (Probe.Output));
               Assert
                 (Ada.Strings.Fixed.Index (Bash_Text, "unresolved") > 0 and then
                  Ada.Strings.Fixed.Index (Zsh_Text, "unresolved") > 0 and then
                  Ada.Strings.Fixed.Index (Fish_Text, "unresolved") > 0,
                  "completion assets omitted the aggregate unresolved task status");
               for Status in Improve.Tasks.Operational_Status loop
                  declare Value : constant String := Improve.Tasks.Image (Status); begin
                     Assert
                       (Ada.Strings.Fixed.Index (Bash_Text, Value) > 0 and then
                        Ada.Strings.Fixed.Index (Zsh_Text, Value) > 0 and then
                        Ada.Strings.Fixed.Index (Fish_Text, Value) > 0,
                        "completion assets omitted task status " & Value);
                  end;
               end loop;
            end;
         when Invalid_Smoke =>
            declare
               Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Args ("unknown"));
               JSON_Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("unknown|--format|json"));
            begin
               Assert
                 (Result.Exit_Code = 2 and then Length (Result.Output) = 0 and then Length (Result.Errors) > 0 and then
                  JSON_Result.Exit_Code = 2 and then
                  Ada.Strings.Fixed.Index (To_String (JSON_Result.Errors), """command"":""error""") > 0 and then
                  Ada.Strings.Fixed.Index (To_String (JSON_Result.Errors), "IMP-E-ARGUMENT") > 0,
                  "invalid command did not observe the output contract");
            end;
      end case;
   end Run_Test;
   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Case_Access'(new Case_Test (Id)));
      end loop;
      return Result;
   end Suite;
end Improve_CLI_Test_Suite;
