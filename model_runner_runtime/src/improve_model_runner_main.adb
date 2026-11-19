--  The embedded runtime turns terminal interrupts into cooperative cancellation.
pragma Unreserve_All_Interrupts;

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Improve.CLI;
with Improve.Config;
with Improve.Refinement.Model_Adapter;
with Improve.Refinement.Model_Runner_Client;
with Improve.Refinement.Model_Runner_Runtime;
with Improve.Text;
with Model_Runner.Errors;
with Model_Runner.Cancellation;
with Model_Runner.Platform;
with Model_Runner.Platform.Signals;
with Model_Runner.Progress;

--  Optional Improve CLI adapter with local Model Runner inference enabled.
procedure Improve_Model_Runner_Main is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_64;
   use type Model_Runner.Progress.Event_Kind;
   use type Model_Runner.Progress.Generation_Stage;

   function Load_Label (Value : Model_Runner.Progress.Load_Stage) return String is
     (Improve.Text.Message
        (case Value is
            when Model_Runner.Progress.Opening_Model => "progress.load.opening_model",
            when Model_Runner.Progress.Reading_Header => "progress.load.reading_header",
            when Model_Runner.Progress.Reading_Metadata => "progress.load.reading_metadata",
            when Model_Runner.Progress.Reading_Tensor_Descriptors => "progress.load.reading_tensors",
            when Model_Runner.Progress.Validating_Model => "progress.load.validating_model",
            when Model_Runner.Progress.Loading_Tokenizer => "progress.load.loading_tokenizer",
            when Model_Runner.Progress.Compiling_Template => "progress.load.compiling_template",
            when Model_Runner.Progress.Selecting_Architecture => "progress.load.selecting_architecture",
            when Model_Runner.Progress.Selecting_Backend => "progress.load.selecting_backend",
            when Model_Runner.Progress.Planning_Memory => "progress.load.planning_memory",
            when Model_Runner.Progress.Preparing_Tensors => "progress.load.preparing_tensors",
            when Model_Runner.Progress.Repacking_Weights => "progress.load.repacking_weights",
            when Model_Runner.Progress.Finalizing_Model => "progress.load.finalizing_model",
            when Model_Runner.Progress.Hashing_Model => "progress.load.hashing_model",
            when Model_Runner.Progress.Model_Ready => "progress.load.model_ready"));

   function Generation_Label (Value : Model_Runner.Progress.Generation_Stage) return String is
     (Improve.Text.Message
        (case Value is
            when Model_Runner.Progress.Prompt_Rendered => "progress.generation.prompt_rendered",
            when Model_Runner.Progress.Prompt_Tokenized => "progress.generation.prompt_tokenized",
            when Model_Runner.Progress.Prefill_Started => "progress.generation.prefill_started",
            when Model_Runner.Progress.Prefill_Progress => "progress.generation.prefill_progress",
            when Model_Runner.Progress.Generation_Started => "progress.generation.started",
            when Model_Runner.Progress.Token_Produced => "progress.generation.token_produced",
            when Model_Runner.Progress.Generation_Completed => "progress.generation.completed"));

   type CLI_Observer is new Model_Runner.Progress.Observer with record
      Last_Token : Interfaces.Unsigned_64 := 0;
   end record;

   overriding procedure Notify
     (Self : in out CLI_Observer;
      Item : Model_Runner.Progress.Event) is
      function Number (Value : Interfaces.Unsigned_64) return String is
        (Ada.Strings.Fixed.Trim (Interfaces.Unsigned_64'Image (Value), Ada.Strings.Both));
   begin
      if Item.Kind = Model_Runner.Progress.Load_Event then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "model: " & Load_Label (Item.Load) &
            (if Item.Total = 0 then ""
             else " " & Number (Item.Completed) & "/" & Number (Item.Total)));
      elsif Item.Generation /= Model_Runner.Progress.Token_Produced or else
        Item.Completed = 1 or else Item.Completed >= Self.Last_Token + 16
      then
         Self.Last_Token := Item.Completed;
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "model: " & Generation_Label (Item.Generation) &
            (if Item.Completed = 0 then "" else " " & Number (Item.Completed)));
      end if;
   end Notify;

   Arguments : Improve.CLI.String_Vectors.Vector;
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      Arguments.Append (Ada.Command_Line.Argument (Index));
   end loop;

   declare
      Item : constant Improve.CLI.Invocation := Improve.CLI.Parse (Arguments);
      Configuration : constant Improve.Config.Loaded_Configuration :=
        Improve.CLI.Configuration_For (Arguments);
      Settings : Improve.Config.Settings renames Configuration.Values;
   begin
      if not Settings.Agent_Enabled then
         Ada.Command_Line.Set_Exit_Status
           (Ada.Command_Line.Exit_Status (Improve.CLI.Run));
         return;
      end if;

      declare
         Runtime : aliased Improve.Refinement.Model_Runner_Runtime.Runtime;
         Cancel  : aliased Model_Runner.Cancellation.Token;
         Reporter : aliased CLI_Observer;
         Signals_Installed : Boolean;
         Status  : Model_Runner.Errors.Error_Info;
         Show_Progress : constant Boolean :=
           not Item.Quiet and then
           (case Item.Progress is
               when Improve.CLI.Progress_Always => True,
               when Improve.CLI.Progress_Never => False,
               when Improve.CLI.Progress_Auto => Model_Runner.Platform.Is_Terminal (2));
      begin
         Model_Runner.Platform.Signals.Install (Cancel'Unchecked_Access, Signals_Installed);
         if Item.Verbose and then not Signals_Installed then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "model: interrupt cancellation unavailable: " & Model_Runner.Platform.Signals.Failure_Name);
         end if;
         Improve.Refinement.Model_Runner_Runtime.Open
           (Runtime,
            To_String (Settings.Agent_Model),
            To_String (Settings.Agent_Model_Path),
            Options =>
              (Cancel   => Cancel'Unchecked_Access,
               Observer => (if Show_Progress then Reporter'Unchecked_Access else null),
               others   => <>),
            Status => Status);
         if Model_Runner.Cancellation.Is_Cancelled (Cancel'Unchecked_Access) then
            Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
            Model_Runner.Platform.Signals.Remove;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, Improve.Text.Message ("progress.cancelled"));
            Ada.Command_Line.Set_Exit_Status
              (Ada.Command_Line.Exit_Status (Improve.CLI.Interrupted_Exit));
            return;
         end if;
         declare
            Client : aliased Improve.Refinement.Model_Runner_Client.Client :=
              Improve.Refinement.Model_Runner_Client.Create
                (Runtime'Access, To_String (Settings.Agent_Model));
            Provider : aliased Improve.Refinement.Model_Adapter.Provider (Client'Access);
            Code : constant Natural := Improve.CLI.Run (Provider'Access);
         begin
            Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
            Model_Runner.Platform.Signals.Remove;
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Code));
         end;
      exception
         when others =>
            Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
            Model_Runner.Platform.Signals.Remove;
            raise;
      end;
   end;
exception
   when Improve.Cancelled_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, Improve.Text.Message ("progress.cancelled"));
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Exit_Status (Improve.CLI.Interrupted_Exit));
   when Error : Improve.Argument_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "improve-model-runner: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Exit_Status (Improve.CLI.Argument_Exit));
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "improve-model-runner: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status
        (Ada.Command_Line.Exit_Status (Improve.CLI.Failure_Exit));
end Improve_Model_Runner_Main;
