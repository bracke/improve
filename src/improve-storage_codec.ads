with Ada.Calendar;
with Ada.Strings.Wide_Wide_Unbounded;
with Improve.Model;

--  Canonical text encoding used by Improve persistence records.
package Improve.Storage_Codec is
   --  Internal, length-delimited and escaped encodings shared by storage components.

   function Encode (Text : String) return Wide_Wide_String;
   --  Decode UTF-8 bytes into database text.
   --  @param Text UTF-8 text.
   --  @return Wide-wide database text.

   function Decode (Text : Wide_Wide_String) return String;
   --  Encode database text as UTF-8 bytes.
   --  @param Text Wide-wide database text.
   --  @return UTF-8 text.

   function WW (Text : String) return Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
   --  Convert UTF-8 text to an unbounded database string.
   --  @param Text UTF-8 text.
   --  @return Unbounded database text.

   function S (Text : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String) return String;
   --  Convert unbounded database text to UTF-8.
   --  @param Text Unbounded database text.
   --  @return UTF-8 text.

   function Field (Payload, Name : String) return String;
   --  Read and unescape a required named payload field.
   --  @param Payload Persisted key-value payload.
   --  @param Name Required field name.
   --  @return Decoded field value.

   function Has_Field (Payload, Name : String) return Boolean;
   --  Test whether a payload contains a named field.
   --  @param Payload Persisted key-value payload.
   --  @param Name Field name.
   --  @return True when the field is present.

   function Field_Or (Payload, Name, Default : String) return String;
   --  Read a named field or return a default value.
   --  @param Payload Persisted key-value payload.
   --  @param Name Field name.
   --  @param Default Value returned when the field is absent.
   --  @return Decoded field value or Default.

   function Pair (Name, Value : String) return String;
   --  Encode one named payload field.
   --  @param Name Field name.
   --  @param Value Unescaped field value.
   --  @return Persisted key-value line.

   function Number (Value : Natural) return String;
   --  Render a natural number without padding.
   --  @param Value Number to render.
   --  @return Canonical decimal image.

   function Boolean_Image (Value : Boolean) return String;
   --  Render a Boolean in lower case.
   --  @param Value Boolean to render.
   --  @return Canonical Boolean image.

   function Pack (Values : Improve.Model.UString_Vectors.Vector) return String;
   --  Encode a vector using unambiguous length-delimited elements.
   --  @param Values Values to encode.
   --  @return Canonical packed vector.

   function Unpack
     (Text          : String;
      Maximum_Items : Natural := 10_000;
      Maximum_Bytes : Natural := 1_048_576) return Improve.Model.UString_Vectors.Vector;
   --  Decode a length-delimited vector, rejecting malformed input.
   --  @param Text Packed vector.
   --  @param Maximum_Items Maximum decoded elements.
   --  @param Maximum_Bytes Maximum total encoded bytes.
   --  @return Decoded values.

   function Timestamp (Value : Ada.Calendar.Time) return String;
   --  Render a UTC timestamp for persistence.
   --  @param Value Time to render.
   --  @return Canonical timestamp.

   function Parse_Time (Text : String) return Ada.Calendar.Time;
   --  Parse a persisted UTC timestamp.
   --  @param Text Canonical timestamp.
   --  @return Parsed time.

   function Id_Image (Prefix : String; Id : Positive) return String;
   --  Render a zero-padded public identity.
   --  @param Prefix Identity prefix.
   --  @param Id Positive numeric identity.
   --  @return Public identity image.

   function Plan_Row_Id (Plan_Id : String) return Positive;
   --  Parse and validate a public plan identity.
   --  @param Plan_Id Public plan identity.
   --  @return Positive database row identity.
end Improve.Storage_Codec;
