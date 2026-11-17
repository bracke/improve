--  Validate one candidate plan against persistence write limits.
separate (Improve.Storage)
procedure Validate_Save_Value
  (Value  : Improve.Model.Plan_Revision;
   Limits : Persistence_Limits) is
   Detail_Count      : Natural := 0;
   Association_Count : Natural := 0;

   procedure Require_Text (Text, Context : String) is
   begin
      if Text'Length > Limits.Maximum_Text_Bytes then
         raise Data_Error with Context & " exceeds configured persisted-text limit";
      end if;
   end Require_Text;

   procedure Add_Count (Count, Maximum : Natural; Total : in out Natural; Context : String) is
   begin
      if Count > Maximum - Total then
         raise Data_Error with Context;
      end if;
      Total := Total + Count;
   end Add_Count;

   function Valid_Fingerprint (Fingerprint : String) return Boolean is
   begin
      if Fingerprint'Length /= 71 or else
        Fingerprint (Fingerprint'First .. Fingerprint'First + 6) /= "sha256:"
      then
         return False;
      end if;
      for Index in Fingerprint'First + 7 .. Fingerprint'Last loop
         if Fingerprint (Index) not in '0' .. '9' | 'a' .. 'f' then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Fingerprint;
begin
   if not Valid_Fingerprint (To_String (Value.Fingerprint)) then
      raise Data_Error with "plan revision identity is not a canonical SHA-256 fingerprint";
   elsif Value.Findings.Length > Ada.Containers.Count_Type (Limits.Maximum_Findings) then
      raise Data_Error with "plan exceeds configured finding write limit";
   elsif Value.Tasks.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
      raise Data_Error with "plan exceeds configured task write limit";
   end if;
   Improve.Model.Validate (Value);
   Require_Text (To_String (Value.Fingerprint), "plan revision identity");
   Require_Text (To_String (Value.Review_Status), "plan revision state");
   for Finding of Value.Findings loop
      Require_Text (To_String (Finding.Fingerprint), "finding identity");
      Require_Text (Improve.Model.Image (Finding.Kind), "finding state");
      Require_Text (Finding_Payload (Finding), "finding payload");
   end loop;
   for Spec of Value.Tasks loop
      Add_Count
        (7, Limits.Maximum_Task_Details, Detail_Count,
         "plan exceeds configured task-detail write limit");
      Add_Count
        (Natural (Spec.Relevant_Files.Length) + Natural (Spec.Finding_Keys.Length) +
         Natural (Spec.Dependencies.Length),
         Limits.Maximum_Task_Associations, Association_Count,
         "plan exceeds configured task-association write limit");
      Require_Text (To_String (Spec.Category), "task kind");
      Require_Text (Improve.Model.Image (Spec.Kind), "task state");
      Require_Text (To_String (Spec.Goal), "task goal");
      Require_Text (To_String (Spec.Problem), "task problem");
      Require_Text (To_String (Spec.Evidence), "task evidence");
      Require_Text (To_String (Spec.Out_Of_Scope), "task exclusions");
      Require_Text (To_String (Spec.Requirements), "task requirements");
      Require_Text (To_String (Spec.Acceptance), "task acceptance");
      Require_Text (To_String (Spec.Verification), "task verification");
   end loop;
end Validate_Save_Value;
