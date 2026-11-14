with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;
with Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

package body Improve.Model is
   use Ada.Strings.Unbounded;

   package Task_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package Index_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   type Count_Array is array (Natural range <>) of Natural;
   type Adjacency_Array is array (Natural range <>) of Index_Vectors.Vector;
   type Digest_Array is array (Natural range <>) of UString;

   procedure Analyze_Task_Graph
     (Tasks   : Task_Vectors.Vector;
      Indexes : out Task_Maps.Map;
      Order   : out Index_Vectors.Vector) is
      Count      : constant Natural := Natural (Tasks.Length);
      Remaining  : Count_Array (1 .. Count) := [others => 0];
      Dependents : Adjacency_Array (1 .. Count);
      Ready      : Index_Vectors.Vector;
      Head       : Natural := 1;
   begin
      Indexes.Clear;
      Order.Clear;
      for Index in 1 .. Count loop
         declare Identity : constant String := To_String (Tasks (Index).Id); begin
            if Identity = "" then
               raise Data_Error with "task identity must not be empty";
            elsif Indexes.Contains (Identity) then
               raise Data_Error with "duplicate task identity " & Identity;
            end if;
            Indexes.Insert (Identity, Index);
         end;
      end loop;
      for Index in 1 .. Count loop
         declare Seen : String_Sets.Set; begin
            for Dependency of Tasks (Index).Dependencies loop
               declare Name : constant String := To_String (Dependency); begin
                  if Seen.Contains (Name) then
                     raise Data_Error with "duplicate dependency edge on " & To_String (Tasks (Index).Id);
                  elsif not Indexes.Contains (Name) then
                     raise Data_Error with "unknown task dependency " & Name;
                  elsif Indexes.Element (Name) = Index then
                     raise Data_Error with "task cannot depend on itself: " & To_String (Tasks (Index).Id);
                  end if;
                  Seen.Insert (Name);
                  Remaining (Index) := Remaining (Index) + 1;
                  Dependents (Indexes.Element (Name)).Append (Index);
               end;
            end loop;
         end;
         if Remaining (Index) = 0 then Ready.Append (Index); end if;
      end loop;
      while Head <= Natural (Ready.Length) loop
         declare Current : constant Positive := Ready (Head); begin
            Head := Head + 1;
            Order.Append (Current);
            for Dependent of Dependents (Current) loop
               Remaining (Dependent) := Remaining (Dependent) - 1;
               if Remaining (Dependent) = 0 then Ready.Append (Dependent); end if;
            end loop;
         end;
      end loop;
      if Natural (Order.Length) /= Count then
         for Index in 1 .. Count loop
            if Remaining (Index) > 0 then
               raise Data_Error with "task dependency graph contains a cycle at " & To_String (Tasks (Index).Id);
            end if;
         end loop;
      end if;
   end Analyze_Task_Graph;

   procedure Validate_Task_Graph (Tasks : Task_Vectors.Vector) is
      Indexes : Task_Maps.Map;
      Order   : Index_Vectors.Vector;
   begin
      Analyze_Task_Graph (Tasks, Indexes, Order);
   end Validate_Task_Graph;

   function Canonical_Key (Values : UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Natural'Image (Natural (Values.Length)) & ":");
      for Value of Values loop
         Append (Result, Natural'Image (Length (Value)) & ":" & To_String (Value));
      end loop;
      return To_String (Result);
   end Canonical_Key;

   function Safe_Relative_Path
     (Path          : String;
      Empty_Allowed : Boolean := True) return Boolean is
      Start : Positive := Path'First;
   begin
      if Path = "" then
         return Empty_Allowed;
      end if;
      declare
         Text : constant Wide_Wide_String :=
           Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path);
      begin
         for Value of Text loop
            declare Code : constant Natural := Wide_Wide_Character'Pos (Value); begin
               if Code < 32 or else Code in 127 .. 159 or else
                 Code in 16#061C# | 16#180E# | 16#2028# | 16#2029# | 16#2060# | 16#FEFF# or else
                 Code in 16#200B# .. 16#200F# or else
                 Code in 16#202A# .. 16#202E# or else Code in 16#2066# .. 16#2069#
               then
                  return False;
               end if;
            end;
         end loop;
      end;
      if Path (Path'First) in '/' | '\' or else
        (Path'Length >= 2 and then Path (Path'First + 1) = ':')
      then
         return False;
      end if;
      for Index in Path'Range loop
         if Path (Index) in '/' | '\' then
            if Index = Start or else Path (Start .. Index - 1) in "." | ".." then
               return False;
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return Start <= Path'Last and then Path (Start .. Path'Last) not in "." | "..";
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         return False;
   end Safe_Relative_Path;

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

   function Image (Item : Verification_Scope) return String is
     (case Item is
         when Task_Evaluation    => "task",
         when Plan_Evaluation    => "plan",
         when Project_Evaluation => "project");

   function Finding_Key (Item : Finding_Reference) return String is
   begin
      return Canonical_Key
        ([To_Unbounded_String (Positive'Image (Item.Project_Id)),
          To_Unbounded_String (Ada_Quality.Types.Image (Item.Indicator)),
          Item.Rule, Item.Fingerprint, Item.Semantic_Subject]);
   exception
      when Constraint_Error =>
         raise Data_Error with "finding has an invalid indicator identity";
   end Finding_Key;

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

   procedure Validate (Plan : Plan_Revision) is
      Findings      : String_Sets.Set;
      Raw_Findings  : String_Sets.Set;
      Ambiguous_Raw : String_Sets.Set;
   begin
      if Plan.Baseline.Project_Id /= Plan.Project.Id then
         raise Data_Error with "assessment baseline belongs to a different project";
      end if;
      Validate_Task_Graph (Plan.Tasks);
      for Finding of Plan.Findings loop
         declare
            Fingerprint : constant String := To_String (Finding.Fingerprint);
         begin
            if Finding.Project_Id /= Plan.Project.Id then
               raise Data_Error with "plan finding belongs to a different project";
            elsif Finding.Run_Id /= Plan.Baseline.Run_Id then
               raise Data_Error with "plan finding belongs to a different assessment";
            elsif Fingerprint = "" then
               raise Data_Error with "finding identity must not be empty";
            elsif not Safe_Relative_Path (To_String (Finding.Relative_Path)) then
               raise Data_Error with "unsafe finding path";
            end if;
            declare Identity : constant String := Finding_Key (Finding); begin
               if Findings.Contains (Identity) then
                  raise Data_Error with "duplicate plan finding " & Identity;
               end if;
               Findings.Insert (Identity);
            end;
            if Raw_Findings.Contains (Fingerprint) then
               Ambiguous_Raw.Include (Fingerprint);
            else
               Raw_Findings.Insert (Fingerprint);
            end if;
         end;
      end loop;
      for Spec of Plan.Tasks loop
         declare
            Linked : String_Sets.Set;
            Files  : String_Sets.Set;
         begin
            for File of Spec.Relevant_Files loop
               declare Name : constant String := To_String (File); begin
                  if not Safe_Relative_Path (Name, Empty_Allowed => False) then
                     raise Data_Error with "unsafe task path on " & To_String (Spec.Id);
                  elsif Files.Contains (Name) then
                     raise Data_Error with "duplicate task path on " & To_String (Spec.Id);
                  end if;
                  Files.Insert (Name);
               end;
            end loop;
            for Key of Spec.Finding_Keys loop
               declare Identity : constant String := To_String (Key); begin
                  if Linked.Contains (Identity) then
                     raise Data_Error with "duplicate task finding link on " & To_String (Spec.Id);
                  elsif not Findings.Contains (Identity) and then
                    (not Raw_Findings.Contains (Identity) or else Ambiguous_Raw.Contains (Identity))
                  then
                     raise Data_Error with "task references unknown finding " & Identity;
                  end if;
                  Linked.Insert (Identity);
               end;
            end loop;
         end;
      end loop;
   end Validate;

   function Effective_Task_Contracts
     (Plan : Plan_Revision) return Task_Contract_Binding_Vectors.Vector is
      Count      : constant Natural := Natural (Plan.Tasks.Length);
      Indexes    : Task_Maps.Map;
      Order      : Index_Vectors.Vector;
      Digests    : Digest_Array (1 .. Count);
      Result     : Task_Contract_Binding_Vectors.Vector;
   begin
      Analyze_Task_Graph (Plan.Tasks, Indexes, Order);
      for Index of Order loop
         declare
            Spec     : Task_Specification renames Plan.Tasks (Index);
            Material : Unbounded_String;
         begin
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
         end;
      end loop;
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

