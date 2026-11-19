with Ada.Real_Time;
with Ada.Strings.Unbounded;

with Model_Runner.Generation;

with Improve.Refinement.Codec;

package body Improve.Refinement.Model_Runner_Runtime is
   use Ada.Strings.Unbounded;
   use type Ada.Real_Time.Time;
   use type Model_Runner.Cancellation.Token_Reference;
   use type Model_Runner.Inference.Completion_State;

   procedure Set_Response
     (Response   : out Agent_Response;
      Status     : Response_Status;
      Diagnostic : String) is
   begin
      Response :=
        (Status     => Status,
         Proposals  => <>,
         Diagnostic => To_Unbounded_String (Diagnostic));
   end Set_Response;

   function Error_Diagnostic
     (Status : Model_Runner.Errors.Error_Info) return String is
     (if Model_Runner.Errors.Is_Ok (Status)
      then "model_runner_failure"
      else Model_Runner.Errors.Diagnostic_Code (Status.Code));

   procedure Open
     (Self    : in out Runtime;
      Model   : String;
      Path    : String;
      Options : Model_Runner.Inference.Open_Options := (others => <>);
      Status  : out Model_Runner.Errors.Error_Info) is
   begin
      Close (Self);
      if Model = "" then
         Status := Model_Runner.Errors.Make
           (Model_Runner.Errors.Generation_Invalid_Request);
         return;
      end if;

      Model_Runner.Inference.Prepare
        (Self.Schema, Improve.Refinement.Response_Schema, Status);
      if Model_Runner.Errors.Is_Error (Status) then
         return;
      end if;

      Model_Runner.Inference.Open (Self.Engine, Path, Options, Status);
      if Model_Runner.Errors.Is_Error (Status) then
         Model_Runner.Inference.Close (Self.Schema);
         return;
      end if;

      Model_Runner.Inference.SHA256
        (Self.Engine, Self.Digest, Status,
         Cancel   => Options.Cancel,
         Observer => Options.Observer);
      if Model_Runner.Errors.Is_Error (Status) then
         Close (Self);
         return;
      end if;
      Self.Model_Id := To_Unbounded_String (Model);
      Self.Cancel := Options.Cancel;
      Self.Observer := Options.Observer;
   end Open;

   procedure Close (Self : in out Runtime) is
   begin
      Model_Runner.Inference.Close (Self.Engine);
      Model_Runner.Inference.Close (Self.Schema);
      Self.Model_Id := Null_Unbounded_String;
      Self.Digest := [others => '0'];
      Self.Cancel := null;
      Self.Observer := null;
   end Close;

   function Is_Open (Self : Runtime) return Boolean is
     (Model_Runner.Inference.Is_Open (Self.Engine)
      and then Model_Runner.Inference.Is_Ready (Self.Schema));

   function Provenance
     (Self : Runtime) return Model_Runner.Inference.Model_Provenance is
     (Model_Runner.Inference.Provenance (Self.Engine));

   overriding function Model_SHA256
     (Self : Runtime) return String is
     (Self.Digest);

   overriding function Details
     (Self : Runtime) return Improve.Refinement.Adapter_Provenance is
      Identity : constant Model_Runner.Inference.Model_Provenance := Provenance (Self);
   begin
      return
        (Provider_Id    => Null_Unbounded_String,
         Model_SHA256   => To_Unbounded_String (Self.Digest),
         Canonical_Path => Identity.Canonical_Path,
         Model_Name     => Identity.Name,
         Architecture   => Identity.Architecture,
         Model_Bytes    => Identity.Bytes,
         Model_Parts    => Identity.Parts);
   end Details;

   overriding function Cancellation_Requested (Self : Runtime) return Boolean is
     (Self.Cancel /= null and then Model_Runner.Cancellation.Is_Cancelled (Self.Cancel));

   procedure Configure_Completion
     (Self     : in out Runtime;
      Cancel   : Model_Runner.Cancellation.Token_Reference := null;
      Observer : Model_Runner.Progress.Observer_Reference := null) is
   begin
      Self.Cancel := Cancel;
      Self.Observer := Observer;
   end Configure_Completion;

   overriding function Name (Self : Runtime) return String is
     (if Is_Open (Self)
      then "embedded:sha256:" & Self.Digest
      else "embedded:closed");

   overriding procedure Infer
     (Self                   : in out Runtime;
      Model                  : String;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response)
   is
      Options : constant Model_Runner.Inference.Completion_Options :=
        (Maximum_Tokens       => Maximum_Response_Bytes,
         Maximum_Output_Bytes => Maximum_Response_Bytes,
         Fill_Context         => True,
         Deadline             => Ada.Real_Time.Clock + Ada.Real_Time.Seconds (Timeout_Seconds),
         Cancel               => Self.Cancel,
         Observer             => Self.Observer,
         others               => <>);
      Outcome : Model_Runner.Inference.Completion;
   begin
      if not Is_Open (Self) then
         Set_Response (Response, Agent_Unavailable, "model_runner_not_open");
      elsif Model /= To_String (Self.Model_Id) then
         Set_Response (Response, Agent_Unavailable, "model_identity_mismatch");
      elsif Answer_Schema /= Improve.Refinement.Response_Schema
        or else Answer_Schema /= To_String (Context.Required_Schema)
      then
         Set_Response (Response, Malformed_Response, "response_schema_mismatch");
      else
         Model_Runner.Inference.Complete
           (Self.Engine,
            Improve.Refinement.Codec.Encode_Prompt (Context),
            Self.Schema,
            Options,
            Outcome);
         case Outcome.State is
            when Model_Runner.Inference.Completion_Ready =>
               Improve.Refinement.Codec.Decode_Response
                 (To_String (Outcome.Text), Maximum_Response_Bytes, Response);
            when Model_Runner.Inference.Completion_Timed_Out =>
               Set_Response (Response, Agent_Timed_Out, "model_runner_timed_out");
            when Model_Runner.Inference.Completion_Incomplete =>
               Set_Response
                 (Response,
                  Malformed_Response,
                  "model_runner_incomplete_"
                  & Model_Runner.Generation.Completion_Reason'Image (Outcome.Reason));
            when Model_Runner.Inference.Completion_Output_Limit =>
               Set_Response (Response, Malformed_Response, "model_runner_output_limit");
            when Model_Runner.Inference.Completion_Cancelled =>
               raise Cancelled_Error with "model inference cancelled";
            when Model_Runner.Inference.Completion_Failed =>
               Set_Response (Response, Agent_Unavailable, Error_Diagnostic (Outcome.Error));
         end case;
      end if;
   end Infer;
end Improve.Refinement.Model_Runner_Runtime;
