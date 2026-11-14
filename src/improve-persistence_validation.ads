with Improve.Persistence_Records;

--  Context validation for typed Improve persistence records.
package Improve.Persistence_Validation is
   --  Bind decoded payload identities to their owning row or operation.

   procedure Validate
     (Value            : Improve.Persistence_Records.Publication_Data;
      Expected_Plan_Id : String;
      Expected_Revision : Natural := 0);
   --  Require a publication mapping to belong to the expected plan and optional revision.
   --  @param Value Decoded publication mapping.
   --  @param Expected_Plan_Id Owning plan identity.
   --  @param Expected_Revision Owning revision, or zero when any revision is valid.

   procedure Validate
     (Value            : Improve.Persistence_Records.Verification_Data;
      Expected_Plan_Id : String;
      Expected_Revision : Natural := 0;
      Expected_Record_Key : String := "");
   --  Require verification evidence to belong to the expected plan and optional revision.
   --  @param Value Decoded verification evidence.
   --  @param Expected_Plan_Id Owning plan identity.
   --  @param Expected_Revision Owning revision, or zero when any revision is valid.
   --  @param Expected_Record_Key Owning task or aggregate key, or empty when not applicable.

   procedure Validate
     (Value                : Improve.Persistence_Records.Approval_Data;
      Expected_Plan_Id     : String;
      Expected_Revision    : Positive;
      Expected_Fingerprint : String);
   --  Require approval evidence to match one exact immutable revision.
   --  @param Value Decoded approval evidence.
   --  @param Expected_Plan_Id Approved plan identity.
   --  @param Expected_Revision Approved revision.
   --  @param Expected_Fingerprint Approved revision fingerprint.

   procedure Validate
     (Value                : Improve.Persistence_Records.Publication_Operation_Data;
      Expected_Plan_Id     : String := "";
      Expected_Revision    : Natural := 0;
      Expected_Fingerprint : String := "");
   --  Require a journal operation to match any supplied publication context.
   --  @param Value Decoded publication operation.
   --  @param Expected_Plan_Id Expected plan identity, or empty when not constrained.
   --  @param Expected_Revision Expected revision, or zero when not constrained.
   --  @param Expected_Fingerprint Expected fingerprint, or empty when not constrained.

   function Operation_Key
     (Value : Improve.Persistence_Records.Publication_Operation_Data) return String;
   --  Return the canonical idempotency key for a publication operation.
   --  @param Value Typed publication operation.
   --  @return Canonical operation identity.
end Improve.Persistence_Validation;
