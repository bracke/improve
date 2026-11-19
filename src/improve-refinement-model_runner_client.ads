with Ada.Strings.Unbounded;
with Improve.Refinement.Model_Adapter;

--  First-party typed bridge from Improve refinement to an in-process model_runner session.
package Improve.Refinement.Model_Runner_Client is
   --  Typed optional inference bridge over an in-process model_runner session.

   type Session is limited interface;
   --  In-process inference session supplied by an optional model_runner runtime.

   function Name (Self : Session) return String is abstract;
   --  Return the stable session identity.
   --  @param Self In-process model_runner session.
   --  @return Stable bounded session identity.

   function Model_SHA256 (Self : Session) return String is abstract;
   --  Return the exact open-model digest when available.
   --  @param Self In-process model_runner session.
   --  @return Lower-case SHA-256 or an empty string.

   function Details
     (Self : Session) return Improve.Refinement.Adapter_Provenance is abstract;
   --  Return typed diagnostics for the open model.
   --  @param Self In-process model_runner session.
   --  @return Model path, architecture, size, parts, and identity information.

   function Cancellation_Requested (Self : Session) return Boolean is abstract;
   --  Return whether cooperative cancellation was requested.
   --  @param Self In-process model_runner session.
   --  @return True when the enclosing operation must stop without persistence.

   procedure Infer
     (Self                   : in out Session;
      Model                  : String;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response) is abstract;
   --  Perform one bounded schema-constrained inference request.
   --  @param Self In-process model_runner session.
   --  @param Model Explicit model identity selected by Improve's embedding.
   --  @param Context Bounded immutable planning context.
   --  @param Answer_Schema Required structured response schema.
   --  @param Timeout_Seconds Cooperative wall-clock deadline.
   --  @param Maximum_Response_Bytes Maximum accepted response bytes.
   --  @param Response Typed completion result.

   type Client (Backend : not null access Session'Class) is
     new Improve.Refinement.Model_Adapter.Client with private;
   --  Concrete model client over an in-process model_runner inference session.

   function Create
     (Backend : not null access Session'Class;
      Model   : String) return Client;
   --  Create a typed client for one explicitly selected model.
   --  @param Backend In-process model_runner inference session.
   --  @param Model Explicit nonempty model identity.
   --  @return Typed model client preserving the supplied session and model identity.

   overriding function Name (Self : Client) return String;
   --  Return the stable model_runner client identity.
   --  @param Self Typed model_runner client.
   --  @return Session- and model-qualified client identity.

   overriding function Model_SHA256 (Self : Client) return String;
   --  Return the digest supplied by the model_runner session.
   --  @param Self Typed model_runner client.
   --  @return Lower-case SHA-256 or an empty string.

   overriding function Details
     (Self : Client) return Improve.Refinement.Adapter_Provenance;
   --  Forward typed runtime diagnostics.
   --  @param Self Typed model_runner client.
   --  @return Model path, architecture, size, parts, and identity information.

   overriding function Cancellation_Requested (Self : Client) return Boolean;
   --  Forward cooperative cancellation state.
   --  @param Self Typed model_runner client.
   --  @return True when the enclosing operation must stop without persistence.

   overriding procedure Complete
     (Self                   : in out Client;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response);
   --  Delegate one bounded schema-constrained completion to the configured session.
   --  @param Self Typed model_runner client.
   --  @param Context Bounded immutable planning context.
   --  @param Answer_Schema Required structured response schema.
   --  @param Timeout_Seconds Cooperative wall-clock deadline.
   --  @param Maximum_Response_Bytes Maximum accepted response bytes.
   --  @param Response Typed completion result.
private
   type Client (Backend : not null access Session'Class) is
     new Improve.Refinement.Model_Adapter.Client with record
      Model : Ada.Strings.Unbounded.Unbounded_String;
   end record;
end Improve.Refinement.Model_Runner_Client;
