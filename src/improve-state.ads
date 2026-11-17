with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Model;

--  Persistence-neutral remediation state shared by storage and domain services.
package Improve.State is
   --  Persistence-neutral remediation state shared by storage and domain services.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Owned UTF-8 remediation-state text.

   type Plan_Summary is record
      Plan_Id     : UString;
      Revision    : Positive;
      Project_Id  : Positive;
      Project     : UString;
      Run_Id      : Positive;
      Task_Count  : Natural;
      Fingerprint : UString;
   end record;
   --  Latest immutable revision summary.
   --  @field Plan_Id Stable plan identity.
   --  @field Revision Latest immutable revision.
   --  @field Project_Id Ada Quality project identity.
   --  @field Project Project display name.
   --  @field Run_Id Baseline assessment identity.
   --  @field Task_Count Number of remediation tasks.
   --  @field Fingerprint Revision content fingerprint.

   package Summary_Vectors is new Ada.Containers.Vectors (Positive, Plan_Summary);
   --  Ordered plan summaries.

   type Publication_Record is record
      Improve_Task_Id : UString;
      Harness_Task_Id : UString;
      Origin          : UString;
      Contract        : UString;
      State           : UString;
      Plan_Revision   : Positive := 1;
   end record;
   --  Verified mapping from Improve work to a native harness task.
   --  @field Improve_Task_Id Stable logical remediation task identity.
   --  @field Harness_Task_Id Native model_runner task identity.
   --  @field Origin Authenticated Improve publication origin.
   --  @field Contract Dependency-qualified execution contract.
   --  @field State Cached harness-owned runtime state.
   --  @field Plan_Revision Revision that first published the mapping.

   package Publication_Vectors is new Ada.Containers.Vectors (Positive, Publication_Record);
   --  Ordered native task mappings.

   type Verification_Record is record
      Scope                : Improve.Model.Verification_Scope := Improve.Model.Task_Evaluation;
      Task_Id              : UString;
      Plan_Revision        : Positive := 1;
      Contract_Fingerprint : UString;
      Assessment_Id        : Positive;
      Outcome              : Improve.Model.Quality_Outcome;
      Comparable           : Boolean;
      Explanation          : UString;
   end record;
   --  Append-only independent verification evidence.
   --  @field Scope Evaluation aggregation level.
   --  @field Task_Id Logical task identity for task-scoped evidence.
   --  @field Plan_Revision Exact evaluated plan revision.
   --  @field Contract_Fingerprint Evaluated task or plan contract.
   --  @field Assessment_Id Completed assessment evaluated.
   --  @field Outcome Independent quality outcome.
   --  @field Comparable Whether baseline and current evidence are comparable.
   --  @field Explanation Evidence-based conclusion.

   package Verification_Vectors is new Ada.Containers.Vectors (Positive, Verification_Record);
   --  Ordered independent verification evidence.

   type Inspection_History is record
      Selected_Revision : Positive := 1;
      Publications      : Publication_Vectors.Vector;
      Verifications     : Verification_Vectors.Vector;
   end record;
   --  Publication and verification history read from one state snapshot.
   --  @field Selected_Revision Exact immutable revision selected.
   --  @field Publications Native task mappings visible in the snapshot.
   --  @field Verifications Quality evidence visible in the snapshot.

   type Publication_Operation is record
      Id          : Positive;
      Key         : UString;
      Plan_Id     : UString;
      Revision    : Positive;
      Fingerprint : UString;
      Content_Fingerprint : UString;
      Task_Kind   : UString;
      Task_Ids    : Improve.Model.UString_Vectors.Vector;
   end record;
   --  Pending durable publication authorization.
   --  @field Id Journal operation identity.
   --  @field Key Stable idempotency key.
   --  @field Plan_Id Authorized logical plan identity.
   --  @field Revision Authorized immutable plan revision.
   --  @field Fingerprint Authorized revision fingerprint.
   --  @field Content_Fingerprint Authorized persisted plan content.
   --  @field Task_Kind Authorized native task kind.
   --  @field Task_Ids Authorized logical task identities.

   package Publication_Operation_Vectors is new Ada.Containers.Vectors (Positive, Publication_Operation);
   --  Ordered pending publication operations.
end Improve.State;
