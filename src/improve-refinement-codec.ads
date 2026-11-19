--  Deterministic JSON boundary for model-backed refinement.
package Improve.Refinement.Codec is

   function Encode_Prompt (Context : Planning_Context) return String;
   --  Encode bounded typed planning context as one JSON prompt.
   --  @param Context Immutable context whose text remains explicitly untrusted.
   --  @return Deterministic JSON prompt with stable field ordering.

   procedure Decode_Response
     (Text                   : String;
      Maximum_Response_Bytes : Positive;
      Response               : out Agent_Response);
   --  Decode one structurally valid typed response.
   --  Malformed, oversized, duplicate-key, or out-of-range input returns
   --  Malformed_Response rather than raising.
   --  @param Text Generated JSON text.
   --  @param Maximum_Response_Bytes Maximum accepted encoded size.
   --  @param Response Typed response or a bounded malformed diagnostic.

end Improve.Refinement.Codec;
