with Improve.Storage_Codec;

package body Improve.Persistence_Records is
   use Ada.Strings.Unbounded;
   use Improve.Storage_Codec;
   use type Improve.Model.Verification_Scope;

   LF : constant Character := Character'Val (10);

   procedure Require_Value (Value, Name : String) is
   begin
      if Value = "" then
         raise Data_Error with "stored " & Name & " is empty";
      end if;
   end Require_Value;

   function Scope_Value (Value : String) return Improve.Model.Verification_Scope is
   begin
      if Value = "task" then
         return Improve.Model.Task_Evaluation;
      elsif Value = "plan" then
         return Improve.Model.Plan_Evaluation;
      elsif Value = "project" then
         return Improve.Model.Project_Evaluation;
      end if;
      raise Data_Error with "stored verification scope is invalid: " & Value;
   end Scope_Value;

   function Encode_Publication (Value : Publication_Data) return String is
     (Pair ("plan_id", To_String (Value.Plan_Id)) & LF &
      Pair ("harness_id", To_String (Value.Harness_Id)) & LF &
      Pair ("origin", To_String (Value.Origin)) & LF &
      Pair ("contract", To_String (Value.Contract)) & LF &
      Pair ("core_state", To_String (Value.Core_State)) & LF &
      Pair ("plan_revision", Number (Value.Plan_Revision)));

   function Decode_Publication (Payload : String) return Publication_Data is
      Result : Publication_Data;
   begin
      Result :=
        (Plan_Id       => To_Unbounded_String (Field (Payload, "plan_id")),
         Harness_Id    => To_Unbounded_String (Field (Payload, "harness_id")),
         Origin        => To_Unbounded_String (Field (Payload, "origin")),
         Contract      => To_Unbounded_String (Field_Or (Payload, "contract", "")),
         Core_State    => To_Unbounded_String (Field_Or (Payload, "core_state", "")),
         Plan_Revision => Positive'Value (Field_Or (Payload, "plan_revision", "1")));
      Require_Value (To_String (Result.Plan_Id), "publication plan identity");
      Require_Value (To_String (Result.Harness_Id), "publication harness identity");
      Require_Value (To_String (Result.Origin), "publication origin");
      return Result;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored publication payload is malformed";
   end Decode_Publication;

   function Encode_Verification (Value : Verification_Data) return String is
     (Pair ("plan_id", To_String (Value.Plan_Id)) & LF &
      Pair ("assessment_id", Number (Value.Assessment_Id)) & LF &
      Pair ("plan_revision", Number (Value.Plan_Revision)) & LF &
      Pair ("contract", To_String (Value.Contract)) & LF &
      Pair ("scope", Improve.Model.Image (Value.Scope)) & LF &
      Pair ("task_id", To_String (Value.Task_Id)) & LF &
      Pair ("comparable", Boolean_Image (Value.Comparable)) & LF &
      Pair ("explanation", To_String (Value.Explanation)));

   function Decode_Verification (Payload : String) return Verification_Data is
      Result : Verification_Data;
   begin
      Result :=
        (Plan_Id       => To_Unbounded_String (Field (Payload, "plan_id")),
         Assessment_Id => Positive'Value (Field (Payload, "assessment_id")),
         Plan_Revision => Positive'Value (Field_Or (Payload, "plan_revision", "1")),
         Contract      => To_Unbounded_String (Field_Or (Payload, "contract", "")),
         Scope         => Scope_Value (Field_Or (Payload, "scope", "task")),
         Task_Id       => To_Unbounded_String (Field_Or (Payload, "task_id", "")),
         Comparable    => Boolean'Value (Field (Payload, "comparable")),
         Explanation   => To_Unbounded_String (Field (Payload, "explanation")));
      Require_Value (To_String (Result.Plan_Id), "verification plan identity");
      if Result.Scope /= Improve.Model.Task_Evaluation and then Length (Result.Task_Id) > 0 then
         raise Data_Error with "stored aggregate verification names a task";
      end if;
      return Result;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored verification payload is malformed";
   end Decode_Verification;

   function Encode_Publication_Operation
     (Value : Publication_Operation_Data) return String is
     (Pair ("plan_id", To_String (Value.Plan_Id)) & LF &
      Pair ("revision", Number (Value.Revision)) & LF &
      Pair ("fingerprint", To_String (Value.Fingerprint)) & LF &
      Pair ("content_fingerprint", To_String (Value.Content_Fingerprint)) & LF &
      Pair ("task_kind", To_String (Value.Task_Kind)) & LF &
      Pair ("task_ids", Pack (Value.Task_Ids)));

   function Decode_Publication_Operation
     (Payload       : String;
      Maximum_Tasks : Positive;
      Maximum_Bytes : Positive) return Publication_Operation_Data is
      Result : Publication_Operation_Data;
   begin
      Result :=
        (Plan_Id     => To_Unbounded_String (Field (Payload, "plan_id")),
         Revision    => Positive'Value (Field_Or (Payload, "revision", "1")),
         Fingerprint => To_Unbounded_String (Field_Or (Payload, "fingerprint", "")),
         Content_Fingerprint => To_Unbounded_String (Field_Or (Payload, "content_fingerprint", "")),
         Task_Kind   => To_Unbounded_String (Field_Or (Payload, "task_kind", "")),
         Task_Ids    => Unpack (Field (Payload, "task_ids"), Maximum_Tasks, Maximum_Bytes));
      Require_Value (To_String (Result.Plan_Id), "publication operation plan identity");
      if Result.Task_Ids.Is_Empty then
         raise Data_Error with "stored publication operation has no tasks";
      end if;
      return Result;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored publication operation is malformed";
   end Decode_Publication_Operation;

   function Encode_Approval (Value : Approval_Data) return String is
     (Pair ("plan_id", To_String (Value.Plan_Id)) & LF &
      Pair ("revision", Number (Value.Revision)) & LF &
      Pair ("fingerprint", To_String (Value.Fingerprint)) & LF &
      Pair ("content_fingerprint", To_String (Value.Content_Fingerprint)));

   function Decode_Approval (Payload : String) return Approval_Data is
      Result : Approval_Data;
   begin
      Result :=
        (Plan_Id     => To_Unbounded_String (Field (Payload, "plan_id")),
         Revision    => Positive'Value (Field (Payload, "revision")),
         Fingerprint => To_Unbounded_String (Field_Or (Payload, "fingerprint", "")),
         Content_Fingerprint => To_Unbounded_String (Field_Or (Payload, "content_fingerprint", "")));
      Require_Value (To_String (Result.Plan_Id), "approval plan identity");
      Require_Value (To_String (Result.Fingerprint), "approval fingerprint");
      return Result;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored approval payload is malformed";
   end Decode_Approval;
end Improve.Persistence_Records;
