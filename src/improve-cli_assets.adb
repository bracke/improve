with Ada.Strings.Unbounded;
with Improve.CLI;
with Improve.CLI_Metadata;
with Improve.Tasks;

package body Improve.CLI_Assets is
   use Ada.Strings.Unbounded;
   use type Improve.CLI.Command_Kind;
   use type Improve.CLI_Metadata.Operation_Context;
   use type Improve.CLI_Metadata.Option_Kind;

   LF : constant Character := Character'Val (10);

   function Prose_List (Values : String) return String is
      Result     : Unbounded_String;
      Word_Start : Positive := Values'First;
      Word_Count : Natural := 0;
   begin
      if Values = "" then return ""; end if;
      for Item of Values loop
         if Item = ' ' then Word_Count := Word_Count + 1; end if;
      end loop;
      Word_Count := Word_Count + 1;
      declare
         Current : Natural := 0;
      begin
         for Index in Values'Range loop
            if Values (Index) = ' ' then
               Current := Current + 1;
               Append (Result, Values (Word_Start .. Index - 1));
               Append (Result, (if Current = Word_Count - 1 then ", or " else ", "));
               Word_Start := Index + 1;
            end if;
         end loop;
      end;
      Append (Result, Values (Word_Start .. Values'Last));
      return To_String (Result);
   end Prose_List;

   function POSIX_Task_Status_Assignments (Variable : String) return String is
      Result : Unbounded_String :=
        To_Unbounded_String ("  local " & Variable & "='all unresolved'" & LF);
   begin
      for Status in Improve.Tasks.Operational_Status loop
         Append
           (Result,
            "  " & Variable & "=""$" & Variable & " " & Improve.Tasks.Image (Status) & """" & LF);
      end loop;
      return To_String (Result);
   end POSIX_Task_Status_Assignments;

   function Fish_Task_Status_Assignments return String is
      Result : Unbounded_String := To_Unbounded_String ("set -l improve_statuses 'all unresolved'" & LF);
   begin
      for Status in Improve.Tasks.Operational_Status loop
         Append
           (Result,
            "set improve_statuses ""$improve_statuses " & Improve.Tasks.Image (Status) & """" & LF);
      end loop;
      return To_String (Result);
   end Fish_Task_Status_Assignments;

   function Accepted_By_Every_Command (Option : Improve.CLI_Metadata.Option_Kind) return Boolean is
     (for all Command in Improve.CLI.Command_Kind =>
        Improve.CLI_Metadata.Accepted_By_Command (Option, Command));

   function Accepted_Context_Words (Option : Improve.CLI_Metadata.Option_Kind) return String is
      Result : Unbounded_String;

      procedure Add (Value : String) is
      begin
         if Length (Result) > 0 then Append (Result, ' '); end if;
         Append (Result, Value);
      end Add;
   begin
      for Command in Improve.CLI.Command_Kind loop
         if Improve.CLI_Metadata.Accepted_By_Command (Option, Command) then
            Add (Improve.CLI_Metadata.Command_Name (Command));
         end if;
      end loop;
      for Context in Improve.CLI_Metadata.Operation_Context loop
         if Context /= Improve.CLI_Metadata.No_Operation then
            declare
               Command : constant Improve.CLI.Command_Kind := Improve.CLI_Metadata.Context_Command (Context);
            begin
               if Improve.CLI_Metadata.Accepted_In_Context (Option, Command, Context) then
                  Add
                    (Improve.CLI_Metadata.Command_Name (Command) & ":" &
                     Improve.CLI_Metadata.Context_Name (Context));
               end if;
            end;
         end if;
      end loop;
      return To_String (Result);
   end Accepted_Context_Words;

   function Bash_Completion return String is separate;
   function Zsh_Completion return String is separate;
   function Fish_Completion return String is separate;

   function Completion (Shell : String) return String is
     (if Shell = "bash" then Bash_Completion
      elsif Shell = "zsh" then Zsh_Completion
      elsif Shell = "fish" then Fish_Completion
      else raise Argument_Error with "unsupported completion shell " & Shell);

   function Manpage return String is
   begin
      return
        ".TH IMPROVE 1 """" ""Improve 0.1.0"" ""User Commands""" & LF &
        ".SH NAME" & LF & "improve \- deterministic Ada quality remediation planning" & LF &
        ".SH SYNOPSIS" & LF & ".B improve" & LF & "command [options]" & LF &
        ".SH DESCRIPTION" & LF &
        "Improve reads completed Ada Quality assessments, stores immutable remediation plans, and publishes" & LF &
        "native model_runner tasks." & LF &
        ".SH COMMANDS" & LF & Improve.CLI_Metadata.Command_List & "." & LF &
        ".SH PLAN OPERATIONS" & LF &
        "plan supports " & Prose_List (Improve.CLI_Metadata.Plan_Operation_Words) &
        " in addition to deterministic generation." & LF &
        ".SH AUDIT" & LF &
        "audit PLAN-ID [--revision N] exports immutable provenance, approval, publication, and verification evidence." &
        LF &
        "audit verify FILE checks its canonical digest. Signed artifacts require --verification-key FILE as an " &
        "independent" & LF &
        "trust anchor for the Ed25519 signature." & LF &
        ".SH OUTPUT" & LF &
        "--format accepts " & Prose_List (Improve.CLI_Metadata.Completion_Values (Improve.CLI_Metadata.Format_Option)) &
        " for plan graph. JSON output and JSON errors are single versioned" & LF &
        "documents." & LF &
        ".SH LOCAL REFINEMENT" & LF &
        "--agent-model, --agent-model-path, and --agent-model-sha256 override the optional local runtime. --no-agent " &
        "disables" & LF &
        "refinement for one invocation. --progress accepts " &
        Prose_List (Improve.CLI_Metadata.Completion_Values (Improve.CLI_Metadata.Progress_Option)) &
        "; auto emits runtime progress only when" & LF &
        "standard error is a terminal." & LF &
        ".SH EXIT STATUS" & LF &
        "0 success; 1 unresolved verification or unhealthy diagnostics; 2 invalid input; 3 unavailable evidence; 4 " &
        "storage or" & LF &
        "internal failure; 130 interrupted." & LF &
        ".SH SEE ALSO" & LF & "ada_quality(1), model_runner(1)" & LF;
   end Manpage;
end Improve.CLI_Assets;
