package body Improve.Model is
   use Ada.Strings.Unbounded;
   function Image (Item : Candidate_Kind) return String is
     (case Item is
         when Remediation_Candidate => "remediation",
         when Investigation_Candidate => "investigation",
         when Diagnostic_Candidate => "diagnostic");

   function Image (Item : Priority) return String is
     (case Item is
         when Critical_Priority => "critical",
         when High_Priority => "high",
         when Normal_Priority => "normal",
         when Low_Priority => "low");

   function Image (Item : Quality_Outcome) return String is
     (case Item is
         when Unverified => "unverified",
         when Verified => "verified",
         when Partially_Resolved => "partially_resolved",
         when Still_Failing => "still_failing",
         when Regressed => "regressed",
         when Inconclusive => "inconclusive",
         when Superseded => "superseded");

   function Task_Contract_Fingerprint (Item : Task_Specification) return String is
      Material : Unbounded_String;

      procedure Add (Name, Value : String) is
      begin
         Append (Material, Natural'Image (Name'Length) & ":" & Name);
         Append (Material, Natural'Image (Value'Length) & ":" & Value);
      end Add;

      procedure Add_Vector (Name : String; Values : UString_Vectors.Vector) is
      begin
         Add (Name & ".count", Natural'Image (Natural (Values.Length)));
         for Value of Values loop Add (Name & ".item", To_String (Value)); end loop;
      end Add_Vector;
   begin
      Add ("title", To_String (Item.Title));
      Add ("category", To_String (Item.Category));
      Add ("priority", Image (Item.Task_Priority));
      Add ("goal", To_String (Item.Goal));
      Add ("problem", To_String (Item.Problem));
      Add ("evidence", To_String (Item.Evidence));
      Add_Vector ("relevant_files", Item.Relevant_Files);
      Add ("scope", To_String (Item.Scope));
      Add ("out_of_scope", To_String (Item.Out_Of_Scope));
      Add ("requirements", To_String (Item.Requirements));
      Add ("acceptance", To_String (Item.Acceptance));
      Add ("verification", To_String (Item.Verification));
      Add_Vector ("dependencies", Item.Dependencies);
      Add_Vector ("finding_keys", Item.Finding_Keys);
      Add ("confidence", Natural'Image (Item.Confidence));
      Add ("requires_review", Boolean'Image (Item.Requires_Review));
      Add ("kind", Image (Item.Kind));
      return Stable_Digest (To_String (Material));
   end Task_Contract_Fingerprint;

   function Effective_Task_Contract_Fingerprint
     (Plan    : Plan_Revision;
      Task_Id : UString) return String is
      function Digest
        (Identity : UString;
         Trail    : UString_Vectors.Vector) return String is
         Next_Trail : UString_Vectors.Vector := Trail;
         Material   : Unbounded_String;
      begin
         if Trail.Contains (Identity) then
            raise Data_Error with "task dependency cycle while fingerprinting " & To_String (Identity);
         end if;
         Next_Trail.Append (Identity);
         for Spec of Plan.Tasks loop
            if Spec.Id = Identity then
               if Spec.Dependencies.Is_Empty then
                  return Task_Contract_Fingerprint (Spec);
               end if;
               Append (Material, "contract:" & Task_Contract_Fingerprint (Spec));
               for Dependency of Spec.Dependencies loop
                  declare
                     Name  : constant String := To_String (Dependency);
                     Value : constant String := Digest (Dependency, Next_Trail);
                  begin
                     Append (Material, Natural'Image (Name'Length) & ":" & Name);
                     Append (Material, Natural'Image (Value'Length) & ":" & Value);
                  end;
               end loop;
               return Stable_Digest (To_String (Material));
            end if;
         end loop;
         raise Data_Error with "unknown task dependency while fingerprinting " & To_String (Identity);
      end Digest;
   begin
      return Digest (Task_Id, UString_Vectors.Empty_Vector);
   end Effective_Task_Contract_Fingerprint;
end Improve.Model;

