package body Improve.Refinement.Model_Runner_Client is
   use Ada.Strings.Unbounded;

   function Create
     (Backend : not null access Session'Class;
      Model   : String) return Client is
   begin
      if Model = "" then raise Argument_Error with "model_runner model identity must not be empty"; end if;
      return (Backend => Backend, Model => To_Unbounded_String (Model));
   end Create;

   overriding function Name (Self : Client) return String is
     ("model_runner:" & Model_Runner_Client.Name (Self.Backend.all) & ":" & To_String (Self.Model));

   overriding function Model_SHA256 (Self : Client) return String is
     (Model_Runner_Client.Model_SHA256 (Self.Backend.all));

   overriding function Details
     (Self : Client) return Improve.Refinement.Adapter_Provenance is
     (Model_Runner_Client.Details (Self.Backend.all));

   overriding function Cancellation_Requested (Self : Client) return Boolean is
     (Model_Runner_Client.Cancellation_Requested (Self.Backend.all));

   overriding procedure Complete
     (Self                   : in out Client;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response) is
   begin
      if Answer_Schema = "" then raise Adapter_Error with "model_runner inference requires an answer schema"; end if;
      Infer
        (Self.Backend.all, To_String (Self.Model), Context, Answer_Schema, Timeout_Seconds,
         Maximum_Response_Bytes, Response);
   end Complete;
end Improve.Refinement.Model_Runner_Client;
