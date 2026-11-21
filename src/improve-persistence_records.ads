with Ada.Strings.Unbounded;
with Improve.Model;

--  Typed codecs for Improve-owned persisted entity payloads.
package Improve.Persistence_Records is
   --  Canonical schemas shared by persistence readers and writers.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized persisted text.

   type Publication_Data is record
      Plan_Id       : UString;
      Harness_Id    : UString;
      Origin        : UString;
      Contract      : UString;
      Core_State    : UString;
      Plan_Revision : Positive := 1;
   end record;
   --  Typed payload stored for one native task mapping.
   --  @field Plan_Id Stable Improve plan identity.
   --  @field Harness_Id Native model_runner task identity.
   --  @field Origin Authenticated Improve publication origin.
   --  @field Contract Dependency-qualified execution contract.
   --  @field Core_State Normalized model_runner core task state, or empty in a legacy payload.
   --  @field Plan_Revision Immutable plan revision that published the mapping.

   function Encode_Publication (Value : Publication_Data) return String;
   --  Encode one publication payload canonically.
   --  @param Value Typed publication payload.
   --  @return Canonical persisted representation.
   function Decode_Publication (Payload : String) return Publication_Data;
   --  Decode and validate one publication payload.
   --  @param Payload Persisted publication representation.
   --  @return Validated typed payload.

   type Verification_Data is record
      Plan_Id       : UString;
      Assessment_Id : Positive;
      Plan_Revision : Positive := 1;
      Contract      : UString;
      Scope         : Improve.Model.Verification_Scope := Improve.Model.Task_Evaluation;
      Task_Id       : UString;
      Comparable    : Boolean;
      Explanation   : UString;
   end record;
   --  Typed payload stored for one verification result.
   --  @field Plan_Id Stable Improve plan identity.
   --  @field Assessment_Id Completed assessment evaluated.
   --  @field Plan_Revision Exact immutable plan revision evaluated.
   --  @field Contract Task or plan contract fingerprint evaluated.
   --  @field Scope Typed evaluation scope.
   --  @field Task_Id Logical task identity for task-scoped evidence.
   --  @field Comparable Whether baseline and current evidence are comparable.
   --  @field Explanation Evidence-based conclusion.

   function Encode_Verification (Value : Verification_Data) return String;
   --  Encode one verification payload canonically.
   --  @param Value Typed verification payload.
   --  @return Canonical persisted representation.
   function Decode_Verification (Payload : String) return Verification_Data;
   --  Decode and validate one verification payload.
   --  @param Payload Persisted verification representation.
   --  @return Validated typed payload.

   type Publication_Operation_Data is record
      Plan_Id     : UString;
      Revision    : Positive;
      Fingerprint : UString;
      Content_Fingerprint : UString;
      Task_Kind   : UString;
      Task_Ids    : Improve.Model.UString_Vectors.Vector;
   end record;
   --  Typed payload stored for one pending publication operation.
   --  @field Plan_Id Stable Improve plan identity.
   --  @field Revision Exact authorized immutable revision.
   --  @field Fingerprint Exact revision content fingerprint.
   --  @field Content_Fingerprint Complete persisted plan-content fingerprint.
   --  @field Task_Kind Resolved native task kind authorized by preflight.
   --  @field Task_Ids Exact authorized logical task identities.

   function Encode_Publication_Operation
     (Value : Publication_Operation_Data) return String;
   --  Encode one durable publication operation canonically.
   --  @param Value Typed operation payload.
   --  @return Canonical persisted representation.

   function Decode_Publication_Operation
     (Payload       : String;
      Maximum_Tasks : Positive;
      Maximum_Bytes : Positive) return Publication_Operation_Data;
   --  Decode one operation while enforcing collection and byte limits.
   --  @param Payload Persisted publication operation.
   --  @param Maximum_Tasks Maximum selected task identities.
   --  @param Maximum_Bytes Maximum encoded task-list bytes.
   --  @return Validated typed payload.

   type Approval_Data is record
      Plan_Id     : UString;
      Revision    : Positive;
      Fingerprint : UString;
      Content_Fingerprint : UString;
   end record;
   --  Typed payload stored for one exact-revision approval.
   --  @field Plan_Id Stable Improve plan identity.
   --  @field Revision Exact approved immutable revision.
   --  @field Fingerprint Exact approved revision content fingerprint.
   --  @field Content_Fingerprint Complete approved persisted plan content.

   function Encode_Approval (Value : Approval_Data) return String;
   --  Encode one approval payload canonically.
   --  @param Value Typed approval payload.
   --  @return Canonical persisted representation.
   function Decode_Approval (Payload : String) return Approval_Data;
   --  Decode and validate one approval payload.
   --  @param Payload Persisted approval representation.
   --  @return Validated typed payload.
end Improve.Persistence_Records;
