--  Concrete refinement adapter over a schema-constrained typed model client.
package Improve.Refinement.Model_Adapter is
   type Client is limited interface;
   --  In-process model completion client implemented by a model runtime integration.

   function Name (Self : Client) return String is abstract;
   --  Return the stable model client identity.
   --  @param Self Model client instance.
   --  @return Stable bounded client identity.

   procedure Complete
     (Self                   : in out Client;
      Context                : Planning_Context;
      Answer_Schema          : String;
      Timeout_Seconds        : Positive;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response) is abstract;
   --  Produce a schema-constrained typed response without invoking a subprocess.
   --  @param Self Model client instance.
   --  @param Context Bounded immutable planning context.
   --  @param Answer_Schema Required structured response schema.
   --  @param Timeout_Seconds Cooperative wall-clock deadline.
   --  @param Maximum_Response_Bytes Maximum accepted response bytes.
   --  @param Response Typed completion result.

   type Client_Access is not null access all Client'Class;
   --  Non-null in-process model client reference.

   type Provider (Backend : not null access Client'Class) is new Improve.Refinement.Adapter with null record;
   --  Concrete Improve adapter delegating to one typed schema-aware model client.
   --  @field Backend In-process schema-aware model client.

   overriding function Name (Self : Provider) return String;
   --  Return the model-backed adapter identity.
   --  @param Self Model-backed provider.
   --  @return Stable adapter identity.

   overriding procedure Request
     (Self            : in out Provider;
      Context         : Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Agent_Response);
   --  Request a bounded schema-constrained model completion.
   --  @param Self Model-backed provider.
   --  @param Context Bounded immutable planning context.
   --  @param Timeout_Seconds Cooperative deadline.
   --  @param Response Typed response receiver.
end Improve.Refinement.Model_Adapter;
