with Ada.Directories;
with Ada.Strings.Fixed;
with Interfaces.C;

with Hostkit.Fs;
with Hostkit.Signals;
with Improve.CLI;
with Improve.Refinement.Model_Adapter;
with Improve.Refinement.Model_Runner_Client;
with Improve.Refinement.Model_Runner_Runtime;
with Model_Runner.Cancellation;
with Model_Runner.Errors;
with Model_Runner.Platform.Signals;
with Model_Runner.Progress;
with Project_Tools.Files;
with Runtime_Test_Fixtures;
with Tiny_Model;

--  Deliver a real host SIGINT during inference and verify CLI cancellation remains non-persistent.
procedure Runtime_Signal_Interrupt is
   use type Interfaces.C.int;
   use type Model_Runner.Progress.Event_Kind;
   use type Model_Runner.Progress.Generation_Stage;

   Model_Id : constant String := "signal-integration-model";

   protected Gate is
      entry Wait_Until_Ready;
      procedure Mark_Ready;
      procedure Record_Send (Success : Boolean);
      procedure Record_Timeout;
      function Was_Sent return Boolean;
      function Timed_Out return Boolean;
   private
      Ready   : Boolean := False;
      Sent    : Boolean := False;
      Timeout : Boolean := False;
   end Gate;

   protected body Gate is
      entry Wait_Until_Ready when Ready is
      begin
         null;
      end Wait_Until_Ready;

      procedure Mark_Ready is
      begin
         Ready := True;
      end Mark_Ready;

      procedure Record_Send (Success : Boolean) is
      begin
         Sent := Success;
      end Record_Send;

      procedure Record_Timeout is
      begin
         Timeout := True;
      end Record_Timeout;

      function Was_Sent return Boolean is (Sent);

      function Timed_Out return Boolean is (Timeout);
   end Gate;

   type Pausing_Observer is new Model_Runner.Progress.Observer with record
      Released : Boolean := False;
   end record;

   overriding procedure Notify
     (Self : in out Pausing_Observer;
      Item : Model_Runner.Progress.Event) is
   begin
      if not Self.Released
        and then Item.Kind = Model_Runner.Progress.Generation_Event
        and then Item.Generation = Model_Runner.Progress.Generation_Started
      then
         Self.Released := True;
         Gate.Mark_Ready;
         delay 1.0;
      end if;
   end Notify;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Raise_Signal (Number : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "raise";

   Interrupt_Number : constant Interfaces.C.int :=
     (if Hostkit.Signals.Is_Supported (Hostkit.Signals.Signal_Interrupt)
      then Interfaces.C.int (Hostkit.Signals.Number (Hostkit.Signals.Signal_Interrupt))
      else 2);

begin
   declare
      Root       : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-runtime-signal");
      Database   : constant String := Root & "/quality.db";
      State_Path : constant String := Root & "/state.db";
      Wrong_State : constant String := Root & "/wrong-state.db";
      Target     : constant String := Root & "/project";
      Model_Path : constant String := Root & "/signal.gguf";
      Project    : Positive;
      Runtime    : aliased Improve.Refinement.Model_Runner_Runtime.Runtime;
      Cancel     : aliased Model_Runner.Cancellation.Token;
      Observer   : aliased Pausing_Observer;
      Status     : Model_Runner.Errors.Error_Info;
      Installed  : Boolean := False;
   begin
      Runtime_Test_Fixtures.Build_Quality_Fixture (Database, Target, Project);
      Tiny_Model.Write
        (Model_Path, Room => 8_192, Forced_Output => "{""proposals"":[]}", Forced_Output_Parts => 2);
      Model_Runner.Platform.Signals.Install (Cancel'Unchecked_Access, Installed);
      Check (Installed, "runtime could not install its SIGINT bridge");
      Improve.Refinement.Model_Runner_Runtime.Open
        (Runtime, Model_Id, Model_Path,
         Options => (Cancel => Cancel'Unchecked_Access, Observer => Observer'Unchecked_Access, others => <>),
         Status => Status);
      Check (Model_Runner.Errors.Is_Ok (Status), "signal test model did not open");

      declare
         task Signaler;

         task body Signaler is
         begin
            select
               Gate.Wait_Until_Ready;
               Gate.Record_Send (Raise_Signal (Interrupt_Number) = 0);
            or
               delay 10.0;
               Gate.Record_Timeout;
            end select;
         end Signaler;

         Client : aliased Improve.Refinement.Model_Runner_Client.Client :=
           Improve.Refinement.Model_Runner_Client.Create (Runtime'Access, Model_Id);
         Provider : aliased Improve.Refinement.Model_Adapter.Provider (Client'Access);
         Result : Improve.CLI.Outcome;
         CLI_Arguments : Improve.CLI.String_Vectors.Vector;
         Wrong_Arguments : Improve.CLI.String_Vectors.Vector;
      begin
         CLI_Arguments.Append ("plan");
         CLI_Arguments.Append ("--database");
         CLI_Arguments.Append (Database);
         CLI_Arguments.Append ("--state");
         CLI_Arguments.Append (State_Path);
         CLI_Arguments.Append ("--project");
         CLI_Arguments.Append (Ada.Strings.Fixed.Trim (Positive'Image (Project), Ada.Strings.Both));
         CLI_Arguments.Append ("--agent-model");
         CLI_Arguments.Append (Model_Id);
         CLI_Arguments.Append ("--agent-model-path");
         CLI_Arguments.Append (Model_Path);
         CLI_Arguments.Append ("--progress");
         CLI_Arguments.Append ("never");
         Wrong_Arguments := CLI_Arguments;
         Wrong_Arguments.Replace_Element (5, Wrong_State);
         Wrong_Arguments.Append ("--agent-model-sha256");
         Wrong_Arguments.Append (String'([1 .. 64 => '0']));
         declare
            Wrong : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute (Wrong_Arguments, Provider'Access);
         begin
            Check
              (Wrong.Exit_Code = Improve.CLI.Unavailable_Exit and then
               not Ada.Directories.Exists (Wrong_State),
               "wrong model digest was accepted or persisted");
         end;
         Result := Improve.CLI.Execute (CLI_Arguments, Provider'Access);
         Check (not Gate.Timed_Out, "SIGINT sender timed out before generation started");
         Check (Gate.Was_Sent, "host refused the SIGINT delivery");
         Check (Result.Exit_Code = Improve.CLI.Interrupted_Exit, "SIGINT did not produce CLI exit 130");
         Check (not Ada.Directories.Exists (State_Path), "SIGINT allowed plan persistence");
      end;

      Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
      Model_Runner.Platform.Signals.Remove;
      Project_Tools.Files.Delete_Tree (Root);
   exception
      when others =>
         Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
         if Installed then Model_Runner.Platform.Signals.Remove; end if;
         if Ada.Directories.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
         raise;
   end;
end Runtime_Signal_Interrupt;
