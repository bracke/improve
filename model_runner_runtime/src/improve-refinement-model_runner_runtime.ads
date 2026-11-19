with Model_Runner.Errors;
with Model_Runner.Inference;
with Model_Runner.Cancellation;
with Model_Runner.Progress;

with Improve.Refinement.Model_Runner_Client;

--  Optional in-process Model Runner implementation of Improve's typed client.
package Improve.Refinement.Model_Runner_Runtime is

   type Runtime is limited new Improve.Refinement.Model_Runner_Client.Session with private;
   --  One reusable local model session with a precompiled response schema.

   procedure Open
     (Self    : in out Runtime;
      Model   : String;
      Path    : String;
      Options : Model_Runner.Inference.Open_Options := (others => <>);
      Status  : out Model_Runner.Errors.Error_Info);
   --  Compile Improve's response schema and open a local GGUF model.
   --  @param Self Runtime to replace.
   --  @param Model Stable model identity expected by Infer.
   --  @param Path Local GGUF path or first shard path.
   --  @param Options Model loading and session controls.
   --  @param Status Success or a typed schema/model diagnostic.

   procedure Close (Self : in out Runtime);
   --  Release the compiled schema and model session. Idempotent.
   --  @param Self Runtime to close.

   function Is_Open (Self : Runtime) return Boolean;
   --  Return whether both the schema and model session are ready.
   --  @param Self Runtime to inspect.
   --  @return True only after a successful Open and before Close.

   function Provenance
     (Self : Runtime) return Model_Runner.Inference.Model_Provenance;
   --  Return stable metadata for the open model.
   --  @param Self Runtime to inspect.
   --  @return Model Runner provenance, or an empty record when closed.

   overriding function Model_SHA256
     (Self : Runtime) return String;
   --  Return the exact model digest computed by Open.
   --  @param Self Runtime to inspect.
   --  @return Lower-case SHA-256, or all zeroes when closed.

   overriding function Details
     (Self : Runtime) return Improve.Refinement.Adapter_Provenance;
   --  Return typed path, architecture, size, parts, and digest diagnostics.
   --  @param Self Runtime to inspect.
   --  @return Model diagnostics, or an empty record when closed.

   overriding function Cancellation_Requested (Self : Runtime) return Boolean;
   --  Return whether the runtime cancellation token has been set.
   --  @param Self Runtime to inspect.
   --  @return True when the enclosing operation must stop without persistence.

   procedure Configure_Completion
     (Self     : in out Runtime;
      Cancel   : Model_Runner.Cancellation.Token_Reference := null;
      Observer : Model_Runner.Progress.Observer_Reference := null);
   --  Replace cooperative controls forwarded to subsequent Infer calls.
   --  Referenced objects must outlive every call that uses them.
   --  @param Self Runtime to configure.
   --  @param Cancel Cooperative cancellation token, or null.
   --  @param Observer Semantic generation progress receiver, or null.

   overriding function Name (Self : Runtime) return String;
   --  Return the stable runtime identity.
   --  @param Self Runtime to inspect.
   --  @return Embedded runtime and configured model identity.

   overriding procedure Infer
     (Self                   : in out Runtime;
      Model                  : String;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response);
   --  Encode context, run bounded inference, and decode the typed response.
   --  @param Self Open runtime.
   --  @param Model Model identity selected by the caller.
   --  @param Context Bounded planning context.
   --  @param Answer_Schema Improve response schema expected by the caller.
   --  @param Timeout_Seconds Cooperative wall-clock deadline.
   --  @param Maximum_Response_Bytes Maximum generated and decoded bytes.
   --  @param Response Typed Improve response state.

private
   type Runtime is limited new Improve.Refinement.Model_Runner_Client.Session with record
      Engine   : Model_Runner.Inference.Session;
      Schema   : Model_Runner.Inference.Prepared_Schema;
      Model_Id : UString;
      Digest   : Model_Runner.Inference.SHA256_Hex := [others => '0'];
      Cancel   : Model_Runner.Cancellation.Token_Reference := null;
      Observer : Model_Runner.Progress.Observer_Reference := null;
   end record;
end Improve.Refinement.Model_Runner_Runtime;
