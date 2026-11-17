with Ada_Quality.Types;
with Improve.Model;
with Improve.Storage;

--  Scalar decoding and payload guards shared by Improve persistence operations.
private package Improve.Storage_Values is
   --  Typed scalar decoding and bounded-payload validation for persisted values.

   function Priority_Value (Text : String) return Improve.Model.Priority;
   --  Decode a persisted remediation priority.
   --  @param Text Stable lowercase priority spelling.
   --  @return Corresponding remediation priority.

   function Kind_Value (Text : String) return Improve.Model.Candidate_Kind;
   --  Decode a persisted candidate kind.
   --  @param Text Stable lowercase candidate-kind spelling.
   --  @return Corresponding candidate kind.

   function Indicator_Value (Text : String) return Ada_Quality.Types.Indicator_Id;
   --  Decode a persisted Ada Quality indicator identity.
   --  @param Text Stable indicator spelling.
   --  @return Corresponding Ada Quality indicator identity.

   function Parse_Outcome (Text : String) return Improve.Model.Quality_Outcome;
   --  Decode a persisted quality outcome.
   --  @param Text Stable lowercase quality-outcome spelling.
   --  @return Corresponding quality outcome.

   procedure Require_Payload_Limit
     (Text    : String;
      Limits  : Improve.Storage.Persistence_Limits;
      Context : String);
   --  Reject persisted text before parsing when it exceeds the configured row budget.
   --  @param Text Persisted payload to validate.
   --  @param Limits Configured persistence limits.
   --  @param Context Diagnostic context for a rejected payload.
end Improve.Storage_Values;
