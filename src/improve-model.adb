with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package body Improve.Model is
   use Ada.Strings.Unbounded;

   function Canonical_Key (Values : UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Natural'Image (Natural (Values.Length)) & ":");
      for Value of Values loop
         Append (Result, Natural'Image (Length (Value)) & ":" & To_String (Value));
      end loop;
      return To_String (Result);
   end Canonical_Key;

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

      package Index_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Positive);

      type Count_Array is array (Natural range <>) of Natural;
      type Adjacency_Array is array (Natural range <>) of Index_Vectors.Vector;
      type Digest_Array is array (Natural range <>) of UString;

      Count      : constant Natural := Natural (Plan.Tasks.Length);
      Indexes    : Task_Maps.Map;
      Remaining  : Count_Array (1 .. Count) := [others => 0];
      Dependents : Adjacency_Array (1 .. Count);
      Digests    : Digest_Array (1 .. Count);
      Ready      : Index_Vectors.Vector;
      Head       : Natural := 1;
      Visited    : Natural := 0;
      Result     : Task_Contract_Binding_Vectors.Vector;
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
         for Dependency of Plan.Tasks (Index).Dependencies loop
            declare Name : constant String := To_String (Dependency); begin
               if not Indexes.Contains (Name) then
                  raise Data_Error with "unknown task dependency while fingerprinting " & Name;
               end if;
               Remaining (Index) := Remaining (Index) + 1;
               Dependents (Indexes.Element (Name)).Append (Index);
            end;
         end loop;
         if Remaining (Index) = 0 then Ready.Append (Index); end if;
      end loop;
      while Head <= Natural (Ready.Length) loop
         declare
            Index    : constant Positive := Ready (Head);
            Spec     : Task_Specification renames Plan.Tasks (Index);
            Material : Unbounded_String;
         begin
            Head := Head + 1;
            Visited := Visited + 1;
            if Spec.Dependencies.Is_Empty then
               Digests (Index) := To_Unbounded_String (Task_Contract_Fingerprint (Spec));
            else
               Append (Material, "contract:" & Task_Contract_Fingerprint (Spec));
               for Dependency of Spec.Dependencies loop
                  declare
                     Name  : constant String := To_String (Dependency);
                     Value : constant String := To_String (Digests (Indexes.Element (Name)));
                  begin
                     Append (Material, Natural'Image (Name'Length) & ":" & Name);
                     Append (Material, Natural'Image (Value'Length) & ":" & Value);
                  end;
               end loop;
               Digests (Index) := To_Unbounded_String (Stable_Digest (To_String (Material)));
            end if;
            for Dependent of Dependents (Index) loop
               Remaining (Dependent) := Remaining (Dependent) - 1;
               if Remaining (Dependent) = 0 then Ready.Append (Dependent); end if;
            end loop;
         end;
      end loop;
      if Visited /= Count then
         raise Data_Error with "task dependency graph contains a cycle while fingerprinting";
      end if;
      for Index in 1 .. Count loop
         Result.Append
           (Task_Contract_Binding'
              (Task_Id     => Plan.Tasks (Index).Id,
               Fingerprint => Digests (Index)));
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

