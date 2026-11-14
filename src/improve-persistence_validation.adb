with Ada.Strings.Unbounded;
with Improve.Model;
with Improve.Storage_Codec;

package body Improve.Persistence_Validation is
   use Ada.Strings.Unbounded;
   use Improve.Storage_Codec;
   use type Improve.Model.Verification_Scope;

   procedure Validate
     (Value             : Improve.Persistence_Records.Publication_Data;
      Expected_Plan_Id  : String;
      Expected_Revision : Natural := 0) is
   begin
      if To_String (Value.Plan_Id) /= Expected_Plan_Id then
         raise Data_Error with "publication mapping belongs to another plan";
      elsif Expected_Revision > 0 and then Value.Plan_Revision /= Expected_Revision then
         raise Data_Error with "publication mapping belongs to another plan revision";
      end if;
   end Validate;

   procedure Validate
     (Value             : Improve.Persistence_Records.Verification_Data;
      Expected_Plan_Id  : String;
      Expected_Revision : Natural := 0;
      Expected_Record_Key : String := "") is
      Record_Key : constant String :=
        (case Value.Scope is
            when Improve.Model.Task_Evaluation =>
              (if Length (Value.Task_Id) > 0 then To_String (Value.Task_Id) else Expected_Record_Key),
            when Improve.Model.Plan_Evaluation => "@plan",
            when Improve.Model.Project_Evaluation => "@project");
   begin
      if To_String (Value.Plan_Id) /= Expected_Plan_Id then
         raise Data_Error with "verification evidence belongs to another plan";
      elsif Expected_Revision > 0 and then Value.Plan_Revision /= Expected_Revision then
         raise Data_Error with "verification evidence belongs to another plan revision";
      elsif Value.Scope = Improve.Model.Task_Evaluation and then Record_Key = "" then
         raise Data_Error with "task verification has no persisted task identity";
      elsif Expected_Record_Key /= "" and then Record_Key /= Expected_Record_Key then
         raise Data_Error with "verification evidence key does not match its payload";
      end if;
   end Validate;

   procedure Validate
     (Value                : Improve.Persistence_Records.Approval_Data;
      Expected_Plan_Id     : String;
      Expected_Revision    : Positive;
      Expected_Fingerprint : String) is
   begin
      if To_String (Value.Plan_Id) /= Expected_Plan_Id then
         raise Data_Error with "approval belongs to another plan";
      elsif Value.Revision /= Expected_Revision then
         raise Data_Error with "approval belongs to another plan revision";
      elsif To_String (Value.Fingerprint) /= Expected_Fingerprint then
         raise Data_Error with "approval fingerprint does not match its plan revision";
      end if;
   end Validate;

   procedure Validate
     (Value                : Improve.Persistence_Records.Publication_Operation_Data;
      Expected_Plan_Id     : String := "";
      Expected_Revision    : Natural := 0;
      Expected_Fingerprint : String := "") is
   begin
      if Expected_Plan_Id /= "" and then To_String (Value.Plan_Id) /= Expected_Plan_Id then
         raise Data_Error with "publication operation belongs to another plan";
      elsif Expected_Revision > 0 and then Value.Revision /= Expected_Revision then
         raise Data_Error with "publication operation belongs to another plan revision";
      elsif Expected_Fingerprint /= "" and then
        To_String (Value.Fingerprint) /= Expected_Fingerprint
      then
         raise Data_Error with "publication operation fingerprint does not match its plan revision";
      end if;
   end Validate;

   function Operation_Key
     (Value : Improve.Persistence_Records.Publication_Operation_Data) return String is
     ("publish:" & To_String (Value.Plan_Id) & ":" & Number (Value.Revision) & ":" &
      Stable_Digest
        (To_String (Value.Task_Kind) & Character'Val (0) & Pack (Value.Task_Ids)));
end Improve.Persistence_Validation;
