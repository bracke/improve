with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Config;

package body Improve.CLI_Metadata is
   use Ada.Strings.Unbounded;
   use type Improve.CLI.Command_Kind;

   function Command_Name (Command : Improve.CLI.Command_Kind) return String is
     (case Command is
         when Improve.CLI.Projects_Command => "projects",
         when Improve.CLI.Findings_Command => "findings",
         when Improve.CLI.Plan_Command => "plan",
         when Improve.CLI.Audit_Command => "audit",
         when Improve.CLI.Apply_Command => "apply",
         when Improve.CLI.Tasks_Command => "tasks",
         when Improve.CLI.Status_Command => "status",
         when Improve.CLI.Refresh_Command => "refresh",
         when Improve.CLI.Verify_Command => "verify",
         when Improve.CLI.Recover_Command => "recover",
         when Improve.CLI.Doctor_Command => "doctor",
         when Improve.CLI.Config_Command => "config",
         when Improve.CLI.Completion_Command => "completion",
         when Improve.CLI.Manpage_Command => "manpage",
         when Improve.CLI.Help_Command => "help",
         when Improve.CLI.Version_Command => "version");

   function Parse_Command (Text : String; Command : out Improve.CLI.Command_Kind) return Boolean is
   begin
      for Candidate in Improve.CLI.Command_Kind loop
         if Command_Name (Candidate) = Text then
            Command := Candidate;
            return True;
         end if;
      end loop;
      Command := Improve.CLI.Help_Command;
      return False;
   end Parse_Command;

   function Command_Words return String is
      Result : Unbounded_String;
   begin
      for Command in Improve.CLI.Command_Kind loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Command_Name (Command));
      end loop;
      return To_String (Result);
   end Command_Words;

   function Command_List return String is
      Result : Unbounded_String;
   begin
      for Command in Improve.CLI.Command_Kind loop
         if Command /= Improve.CLI.Command_Kind'First then
            if Command = Improve.CLI.Completion_Command then
               Append (Result, ',' & Character'Val (10));
            else
               Append (Result, (if Command = Improve.CLI.Command_Kind'Last then ", and " else ", "));
            end if;
         end if;
         Append (Result, Command_Name (Command));
      end loop;
      return To_String (Result);
   end Command_List;

   function Command_Help_Key (Command : Improve.CLI.Command_Kind) return String is
     ("help.cmd." & Command_Name (Command));

   function Plan_Operation_Name (Value : Improve.CLI.Plan_Operation) return String is
     (case Value is
         when Improve.CLI.Create_Plan => "",
         when Improve.CLI.List_Plans => "list",
         when Improve.CLI.Show_Plan => "show",
         when Improve.CLI.Approve_Plan => "approve",
         when Improve.CLI.Diff_Plan => "diff",
         when Improve.CLI.Explain_Plan => "explain",
         when Improve.CLI.Graph_Plan => "graph");

   function Parse_Plan_Operation (Text : String; Value : out Improve.CLI.Plan_Operation) return Boolean is
   begin
      for Candidate in Improve.CLI.Plan_Operation'Succ (Improve.CLI.Create_Plan) .. Improve.CLI.Plan_Operation'Last loop
         if Plan_Operation_Name (Candidate) = Text then
            Value := Candidate;
            return True;
         end if;
      end loop;
      Value := Improve.CLI.Create_Plan;
      return False;
   end Parse_Plan_Operation;

   function Plan_Operation_Words return String is
      Result : Unbounded_String;
   begin
      for Value in Improve.CLI.Plan_Operation'Succ (Improve.CLI.Create_Plan) .. Improve.CLI.Plan_Operation'Last loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Plan_Operation_Name (Value));
      end loop;
      return To_String (Result);
   end Plan_Operation_Words;

   function Positional_Values (Command : Improve.CLI.Command_Kind) return String is
     (case Command is
         when Improve.CLI.Plan_Command => Plan_Operation_Words,
         when Improve.CLI.Audit_Command => "verify",
         when Improve.CLI.Config_Command => "show validate explain",
         when Improve.CLI.Completion_Command => "bash zsh fish",
         when Improve.CLI.Help_Command => Command_Words,
         when others => "");

   function Positional_Value_Allowed (Command : Improve.CLI.Command_Kind; Text : String) return Boolean is
      Values : constant String := Positional_Values (Command);
      First  : Positive := Values'First;
   begin
      if Text = "" then
         return False;
      end if;
      while First <= Values'Last loop
         declare
            Relative_Last : constant Natural := Ada.Strings.Fixed.Index (Values (First .. Values'Last), " ");
            Last : constant Natural := (if Relative_Last = 0 then Values'Last else Relative_Last - 1);
         begin
            if Values (First .. Last) = Text then
               return True;
            end if;
            exit when Relative_Last = 0;
            First := Relative_Last + 1;
         end;
      end loop;
      return False;
   end Positional_Value_Allowed;

   function Progress_Word (Value : Improve.CLI.Progress_Mode) return String is
     (case Value is
         when Improve.CLI.Progress_Auto => "auto",
         when Improve.CLI.Progress_Always => "always",
         when Improve.CLI.Progress_Never => "never");

   function Parse_Progress_Mode (Text : String; Value : out Improve.CLI.Progress_Mode) return Boolean is
   begin
      for Candidate in Improve.CLI.Progress_Mode loop
         if Progress_Word (Candidate) = Text then
            Value := Candidate;
            return True;
         end if;
      end loop;
      Value := Improve.CLI.Progress_Auto;
      return False;
   end Parse_Progress_Mode;

   function Format_Values return String is
      Result : Unbounded_String;
   begin
      for Value in Improve.Config.Output_Format loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Improve.Config.Image (Value));
      end loop;
      return To_String (Result);
   end Format_Values;

   function Color_Values return String is
      Result : Unbounded_String;
   begin
      for Value in Improve.Config.Color_Mode loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Improve.Config.Image (Value));
      end loop;
      return To_String (Result);
   end Color_Values;

   function Progress_Values return String is
      Result : Unbounded_String;
   begin
      for Value in Improve.CLI.Progress_Mode loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Progress_Word (Value));
      end loop;
      return To_String (Result);
   end Progress_Values;

   function Severity_Values return String is
      Result : Unbounded_String;
   begin
      for Value in reverse Improve.Config.Severity_Level loop
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Improve.Config.Image (Value));
      end loop;
      return To_String (Result);
   end Severity_Values;

   function Choice_Display (Option, Values : String) return String is
      Result : Unbounded_String := To_Unbounded_String (Option & ' ');
   begin
      for Item of Values loop
         Append (Result, (if Item = ' ' then '|' else Item));
      end loop;
      return To_String (Result);
   end Choice_Display;

   type Command_Set is array (Improve.CLI.Command_Kind) of Boolean;

   type Option_Specification is record
      Word                   : Unbounded_String;
      Takes_Value            : Boolean;
      File_Value             : Boolean;
      Completion_Values      : Unbounded_String;
      Completion_Description : Unbounded_String;
      Help_Display           : Unbounded_String;
      Help_Key               : Unbounded_String;
      Document_In_Help       : Boolean;
      Accepted_Commands      : Command_Set;
   end record;

   type Value_Arity is (No_Value, Required_Value);
   type Value_Completion is (Plain_Value, File_Path);
   type Help_Visibility is (Visible, Hidden);

   function Make_Specification
     (Word, Values, Description, Display, Key : String;
      Arity                                   : Value_Arity;
      Completion                              : Value_Completion;
      Visibility                              : Help_Visibility;
      Accepted_Commands : Command_Set := [others => True])
      return Option_Specification is
     (Word                   => To_Unbounded_String (Word),
      Takes_Value            => Arity = Required_Value,
      File_Value             => Completion = File_Path,
      Completion_Values      => To_Unbounded_String (Values),
      Completion_Description => To_Unbounded_String (Description),
      Help_Display           => To_Unbounded_String (Display),
      Help_Key               => To_Unbounded_String (Key),
      Document_In_Help       => Visibility = Visible,
      Accepted_Commands      => Accepted_Commands);

   Option_Specifications : constant array (Option_Kind) of Option_Specification :=
     [Config_Option =>
        Make_Specification
          ("--config", "", "configuration file", "--config PATH", "help.opt.config",
           Required_Value, File_Path, Visible),
      Database_Option =>
        Make_Specification
          ("--database", "", "quality database", "--database PATH", "help.opt.database",
           Required_Value, File_Path, Visible),
      State_Option =>
        Make_Specification
          ("--state", "", "Improve state", "--state PATH", "help.opt.state",
           Required_Value, File_Path, Visible),
      Project_Option =>
        Make_Specification
          ("--project", "", "project identity", "--project ID|NAME", "help.opt.project",
           Required_Value, Plain_Value, Visible),
      Format_Option =>
        Make_Specification
          ("--format", Format_Values, "output format", Choice_Display ("--format", Format_Values),
           "help.opt.format", Required_Value, Plain_Value, Visible),
      Color_Option =>
        Make_Specification
          ("--color", Color_Values, "color policy", Choice_Display ("--color", Color_Values), "help.opt.color",
           Required_Value, Plain_Value, Visible),
      Progress_Option =>
        Make_Specification
          ("--progress", Progress_Values, "runtime progress", Choice_Display ("--progress", Progress_Values),
           "help.opt.progress", Required_Value, Plain_Value, Visible),
      Run_Option =>
        Make_Specification
          ("--run", "", "assessment identity", "--run ID", "help.opt.run",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Findings_Command | Improve.CLI.Plan_Command | Improve.CLI.Verify_Command => True,
            others => False]),
      Revision_Option =>
        Make_Specification
          ("--revision", "", "plan revision", "--revision NUMBER", "help.opt.revision",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Plan_Command | Improve.CLI.Tasks_Command | Improve.CLI.Verify_Command |
            Improve.CLI.Audit_Command => True, others => False]),
      Against_Revision_Option =>
        Make_Specification
          ("--against-revision", "", "earlier revision", "--against-revision NUMBER",
           "help.opt.against_revision", Required_Value, Plain_Value, Visible,
           [Improve.CLI.Plan_Command => True, others => False]),
      Task_Option =>
        Make_Specification
          ("--task", "", "Improve task identity", "--task ID", "help.opt.task",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Apply_Command | Improve.CLI.Tasks_Command | Improve.CLI.Verify_Command => True,
            others => False]),
      Status_Option =>
        Make_Specification
          ("--status", "", "task status", "--status STATUS", "help.opt.status",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Tasks_Command => True, others => False]),
      Indicator_Option =>
        Make_Specification
          ("--indicator", "", "finding indicator", "--indicator ID", "help.opt.indicator",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Findings_Command => True, others => False]),
      Severity_Option =>
        Make_Specification
          ("--severity", Severity_Values, "finding severity", "--severity LEVEL",
           "help.opt.severity", Required_Value, Plain_Value, Visible,
           [Improve.CLI.Findings_Command => True, others => False]),
      Path_Option =>
        Make_Specification
          ("--path", "", "finding path", "--path TEXT", "help.opt.path", Required_Value, File_Path, Visible,
           [Improve.CLI.Findings_Command => True, others => False]),
      Limit_Option =>
        Make_Specification
          ("--limit", "", "page size", "--limit N / --cursor N", "help.opt.pagination",
           Required_Value, Plain_Value, Visible,
           [Improve.CLI.Findings_Command | Improve.CLI.Tasks_Command | Improve.CLI.Audit_Command |
            Improve.CLI.Plan_Command => True, others => False]),
      Cursor_Option =>
        Make_Specification
          ("--cursor", "", "page cursor", "--cursor N", "help.opt.pagination",
           Required_Value, Plain_Value, Hidden,
           [Improve.CLI.Findings_Command | Improve.CLI.Tasks_Command | Improve.CLI.Audit_Command |
            Improve.CLI.Plan_Command => True, others => False]),
      Signing_Key_Option =>
        Make_Specification
          ("--signing-key", "", "private signing key", "--signing-key FILE", "help.opt.signing_key",
           Required_Value, File_Path, Visible,
           [Improve.CLI.Audit_Command => True, others => False]),
      Verification_Key_Option =>
        Make_Specification
          ("--verification-key", "", "trusted audit public key", "--verification-key FILE",
           "help.opt.verification_key", Required_Value, File_Path, Visible,
           [Improve.CLI.Audit_Command => True, others => False]),
      Agent_Model_Option =>
        Make_Specification
          ("--agent-model", "", "local model identity", "--agent-model NAME", "help.opt.agent_model",
           Required_Value, Plain_Value, Visible),
      Agent_Model_Path_Option =>
        Make_Specification
          ("--agent-model-path", "", "local GGUF model", "--agent-model-path FILE", "help.opt.agent_model_path",
           Required_Value, File_Path, Visible),
      Agent_Model_SHA256_Option =>
        Make_Specification
          ("--agent-model-sha256", "", "expected model digest", "--agent-model-sha256 HEX",
           "help.opt.agent_model_sha256", Required_Value, Plain_Value, Visible),
      No_Agent_Option =>
        Make_Specification
          ("--no-agent", "", "disable local refinement", "--no-agent", "help.opt.no_agent",
           No_Value, Plain_Value, Visible),
      Dry_Run_Option =>
        Make_Specification
          ("--dry-run", "", "preview without writes", "--dry-run", "help.opt.dry_run",
           No_Value, Plain_Value, Visible,
           [Improve.CLI.Plan_Command | Improve.CLI.Apply_Command => True, others => False]),
      Release_Option =>
        Make_Specification
          ("--release", "", "validate release candidate", "--release", "help.opt.release",
           No_Value, Plain_Value, Visible,
           [Improve.CLI.Doctor_Command => True, others => False]),
      All_Option =>
        Make_Specification
          ("--all", "", "select every project", "--all", "help.opt.all", No_Value, Plain_Value, Visible,
           [Improve.CLI.Status_Command => True, others => False]),
      Verbose_Option =>
        Make_Specification
          ("--verbose", "", "include operational detail", "--verbose", "help.opt.verbose",
           No_Value, Plain_Value, Visible),
      Quiet_Option =>
        Make_Specification
          ("--quiet", "", "suppress nonessential output", "--quiet", "help.opt.quiet",
           No_Value, Plain_Value, Visible),
      Help_Option =>
        Make_Specification
          ("--help", "", "display help", "--help", "help.opt.help", No_Value, Plain_Value, Visible),
      Version_Option =>
        Make_Specification
          ("--version", "", "display version", "--version", "help.opt.version",
           No_Value, Plain_Value, Hidden, [others => False])];

   function Word (Option : Option_Kind) return String is
     (To_String (Option_Specifications (Option).Word));

   function Parse_Option (Text : String; Option : out Option_Kind) return Boolean is
   begin
      for Candidate in Option_Kind loop
         if Word (Candidate) = Text then
            Option := Candidate;
            return True;
         end if;
      end loop;
      Option := Help_Option;
      return False;
   end Parse_Option;

   function Takes_Value (Option : Option_Kind) return Boolean is
     (Option_Specifications (Option).Takes_Value);

   function File_Value (Option : Option_Kind) return Boolean is
     (Option_Specifications (Option).File_Value);

   function Completion_Values (Option : Option_Kind) return String is
     (To_String (Option_Specifications (Option).Completion_Values));

   function Completion_Description (Option : Option_Kind) return String is
     (To_String (Option_Specifications (Option).Completion_Description));

   function Help_Display (Option : Option_Kind) return String is
     (To_String (Option_Specifications (Option).Help_Display));

   function Help_Key (Option : Option_Kind) return String is
     (To_String (Option_Specifications (Option).Help_Key));

   function Document_In_Help (Option : Option_Kind) return Boolean is
     (Option_Specifications (Option).Document_In_Help);

   function Accepted_By_Command
     (Option  : Option_Kind;
      Command : Improve.CLI.Command_Kind) return Boolean is
     (Option_Specifications (Option).Accepted_Commands (Command));

   function Context_Command (Context : Operation_Context) return Improve.CLI.Command_Kind is
     (case Context is
         when Plan_Create_Operation | Plan_List_Operation | Plan_Show_Operation |
              Plan_Approve_Operation | Plan_Diff_Operation | Plan_Explain_Operation |
              Plan_Graph_Operation => Improve.CLI.Plan_Command,
         when Audit_Export_Operation | Audit_Verify_Operation => Improve.CLI.Audit_Command,
         when No_Operation => Improve.CLI.Help_Command);

   function Context_Name (Context : Operation_Context) return String is
     (case Context is
         when No_Operation => "",
         when Plan_Create_Operation => "create",
         when Plan_List_Operation => "list",
         when Plan_Show_Operation => "show",
         when Plan_Approve_Operation => "approve",
         when Plan_Diff_Operation => "diff",
         when Plan_Explain_Operation => "explain",
         when Plan_Graph_Operation => "graph",
         when Audit_Export_Operation => "export",
         when Audit_Verify_Operation => "verify");

   function Accepted_In_Context
     (Option  : Option_Kind;
      Command : Improve.CLI.Command_Kind;
      Context : Operation_Context) return Boolean is
   begin
      if not Accepted_By_Command (Option, Command) then
         return False;
      end if;
      case Context is
         when No_Operation =>
            return True;
         when Plan_Create_Operation | Plan_Approve_Operation =>
            return Option not in Revision_Option | Against_Revision_Option | Limit_Option | Cursor_Option;
         when Plan_List_Operation =>
            return Option not in Revision_Option | Against_Revision_Option;
         when Plan_Show_Operation | Plan_Explain_Operation | Plan_Graph_Operation =>
            return Option not in Against_Revision_Option | Limit_Option | Cursor_Option;
         when Plan_Diff_Operation =>
            return Option not in Limit_Option | Cursor_Option;
         when Audit_Export_Operation =>
            return Option /= Verification_Key_Option;
         when Audit_Verify_Operation =>
            return Option /= Signing_Key_Option;
      end case;
   end Accepted_In_Context;

   function Context_For
     (Command      : Improve.CLI.Command_Kind;
      Plan_Action  : Improve.CLI.Plan_Operation;
      Audit_Verify : Boolean) return Operation_Context is
   begin
      if Command = Improve.CLI.Plan_Command then
         return
           (case Plan_Action is
               when Improve.CLI.Create_Plan => Plan_Create_Operation,
               when Improve.CLI.List_Plans => Plan_List_Operation,
               when Improve.CLI.Show_Plan => Plan_Show_Operation,
               when Improve.CLI.Approve_Plan => Plan_Approve_Operation,
               when Improve.CLI.Diff_Plan => Plan_Diff_Operation,
               when Improve.CLI.Explain_Plan => Plan_Explain_Operation,
               when Improve.CLI.Graph_Plan => Plan_Graph_Operation);
      elsif Command = Improve.CLI.Audit_Command then
         return (if Audit_Verify then Audit_Verify_Operation else Audit_Export_Operation);
      end if;
      return No_Operation;
   end Context_For;

   function Value_Expectation (Option : Option_Kind) return String is
     ("one of " & Completion_Values (Option));
end Improve.CLI_Metadata;
