with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

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

   function Effective_Task_Contracts
     (Plan : Plan_Revision) return Task_Contract_Binding_Vectors.Vector is
      package Task_Maps is new Ada.Containers.Indefinite_Hashed_Maps
        (Key_Type        => String,
         Element_Type    => Positive,
         Hash            => Ada.Strings.Hash,
         Equivalent_Keys => "=");

      type Visit_State is (Unvisited, Visiting, Visited);
      type State_Array is array (Natural range <>) of Visit_State;
      type Digest_Array is array (Natural range <>) of UString;

      Count   : constant Natural := Natural (Plan.Tasks.Length);
      Indexes : Task_Maps.Map;
      States  : State_Array (1 .. Count) := [others => Unvisited];
      Digests : Digest_Array (1 .. Count);
      Result  : Task_Contract_Binding_Vectors.Vector;

      function Digest (Index : Positive) return String is
         Spec     : constant Task_Specification := Plan.Tasks (Index);
         Material : Unbounded_String;
      begin
         if States (Index) = Visiting then
            raise Data_Error with "task dependency cycle while fingerprinting " & To_String (Spec.Id);
         elsif States (Index) = Visited then
            return To_String (Digests (Index));
         end if;

         States (Index) := Visiting;
         if Spec.Dependencies.Is_Empty then
            Digests (Index) := To_Unbounded_String (Task_Contract_Fingerprint (Spec));
         else
            Append (Material, "contract:" & Task_Contract_Fingerprint (Spec));
            for Dependency of Spec.Dependencies loop
               declare
                  Name : constant String := To_String (Dependency);
               begin
                  if not Indexes.Contains (Name) then
                     raise Data_Error with "unknown task dependency while fingerprinting " & Name;
                  end if;
                  declare
                     Value : constant String := Digest (Indexes.Element (Name));
                  begin
                     Append (Material, Natural'Image (Name'Length) & ":" & Name);
                     Append (Material, Natural'Image (Value'Length) & ":" & Value);
                  end;
               end;
            end loop;
            Digests (Index) := To_Unbounded_String (Stable_Digest (To_String (Material)));
         end if;
         States (Index) := Visited;
         return To_String (Digests (Index));
      end Digest;
   begin
      for Index in 1 .. Count loop
         declare
            Identity : constant String := To_String (Plan.Tasks (Index).Id);
         begin
            if Identity = "" then
               raise Data_Error with "task identity must not be empty while fingerprinting";
            elsif Indexes.Contains (Identity) then
               raise Data_Error with "duplicate task identity while fingerprinting " & Identity;
            end if;
            Indexes.Insert (Identity, Index);
         end;
      end loop;
      for Index in 1 .. Count loop
         Result.Append
           (Task_Contract_Binding'
              (Task_Id     => Plan.Tasks (Index).Id,
               Fingerprint => To_Unbounded_String (Digest (Index))));
      end loop;
      return Result;
   end Effective_Task_Contracts;

   function Effective_Task_Contract
     (Bindings : Task_Contract_Binding_Vectors.Vector;
      Task_Id  : UString) return String is
   begin
      for Binding of Bindings loop
         if Binding.Task_Id = Task_Id then
            return To_String (Binding.Fingerprint);
         end if;
      end loop;
      raise Data_Error with "unknown task contract " & To_String (Task_Id);
   end Effective_Task_Contract;

   function Effective_Task_Contract_Fingerprint
     (Plan    : Plan_Revision;
      Task_Id : UString) return String is
      Bindings : constant Task_Contract_Binding_Vectors.Vector := Effective_Task_Contracts (Plan);
   begin
      return Effective_Task_Contract (Bindings, Task_Id);
   end Effective_Task_Contract_Fingerprint;
end Improve.Model;

