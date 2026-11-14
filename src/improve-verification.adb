with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;
with Improve.Findings;
with Ada_Quality.Types;

package body Improve.Verification is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Improve.Model.Quality_Outcome;

   type Evidence_State is (Resolved_Evidence, Outstanding_Evidence, Inconclusive_Evidence);

   package Finding_Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   function Exact_Key
     (Indicator   : Indicator_Id;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String) return String is
     (Improve.Model.Canonical_Key
        ([To_Unbounded_String (Image (Indicator)), Fingerprint]));

   function Semantic_Key (Finding : Improve.Model.Finding_Reference) return String is
     (Improve.Model.Canonical_Key
        ([To_Unbounded_String (Image (Finding.Indicator)), Finding.Rule, Finding.Semantic_Subject]));

   function Semantic_Pair
     (Semantic    : String;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String) return String is
     (Improve.Model.Canonical_Key
        ([To_Unbounded_String (Semantic), Fingerprint]));

   function Baseline_Finding
     (Plan           : Improve.Model.Plan_Revision;
      Indexes        : Finding_Index_Maps.Map;
      Legacy_Indexes : Finding_Index_Maps.Map;
      Ambiguous      : String_Sets.Set;
      Key            : Ada.Strings.Unbounded.Unbounded_String) return Improve.Model.Finding_Reference is
      Identity : constant String := To_String (Key);
   begin
      if Indexes.Contains (Identity) then
         return Plan.Findings (Indexes.Element (Identity));
      elsif Ambiguous.Contains (Identity) then
         raise Data_Error with "task finding identity is ambiguous within its plan";
      elsif not Legacy_Indexes.Contains (Identity) then
         raise Data_Error with "task references an unknown baseline finding";
      end if;
      return Plan.Findings (Legacy_Indexes.Element (Identity));
   end Baseline_Finding;

   function State_Of
     (Original : Improve.Model.Finding_Reference;
      Current  : Improve.Source.Selection;
      Current_Exact : String_Sets.Set;
      Current_Raw_Exact : String_Sets.Set;
      Semantic_Counts : Count_Maps.Map;
      Task_Semantic_Matches : Count_Maps.Map) return Evidence_State is
      Result : constant Indicator_Result := Current.Assessment.Results
        (Current.Assessment.Results.First_Index + Indicator_Id'Pos (Original.Indicator));
      Semantic : constant String := Semantic_Key (Original);
   begin
      if Result.Indicator /= Original.Indicator then
         raise Data_Error with "verification indicator registry order is inconsistent";
      end if;
      if Result.Execution = Succeeded and then Result.Compliance = Pass then
         return Resolved_Evidence;
      elsif Result.Execution = Succeeded and then Result.Compliance = Violation then
         if Original.Indicator_Level then return Outstanding_Evidence; end if;
         if Current_Exact.Contains (Exact_Key (Original.Indicator, Original.Fingerprint)) then
            return Outstanding_Evidence;
         elsif Semantic_Counts.Contains (Semantic) and then
           Semantic_Counts.Element (Semantic) >
             (if Task_Semantic_Matches.Contains (Semantic)
              then Task_Semantic_Matches.Element (Semantic)
              else 0)
         then
            return Inconclusive_Evidence;
         end if;
         return Resolved_Evidence;
      elsif Result.Execution = Failed and then Result.Compliance = Violation then
         if Original.Indicator_Level then return Outstanding_Evidence; end if;
         if Current_Raw_Exact.Contains (Exact_Key (Original.Indicator, Original.Fingerprint)) then
            return Outstanding_Evidence;
         end if;
         return Inconclusive_Evidence;
      else
         return Inconclusive_Evidence;
      end if;
   end State_Of;

   procedure Add_Inconclusive_Tasks
     (Plan        : Improve.Model.Plan_Revision;
      Task_Id     : String;
      Explanation : String;
      Value       : in out Report) is
   begin
      for Spec of Plan.Tasks loop
         if Task_Id = "" or else To_String (Spec.Id) = Task_Id then
            Value.Tasks.Append
              (Task_Result'
                 (Task_Id     => Spec.Id,
                  Outcome     => Improve.Model.Inconclusive,
                  Matched     => 0,
                  Total       => Natural (Spec.Finding_Keys.Length),
                  Explanation => To_Unbounded_String (Explanation)));
         end if;
      end loop;
      if Value.Tasks.Is_Empty then raise Argument_Error with "task does not belong to plan: " & Task_Id; end if;
   end Add_Inconclusive_Tasks;

   function Precedence (Value : Improve.Model.Quality_Outcome) return Natural is
     (case Value is
         when Improve.Model.Regressed => 5,
         when Improve.Model.Inconclusive => 4,
         when Improve.Model.Still_Failing => 3,
         when Improve.Model.Partially_Resolved => 2,
         when Improve.Model.Verified => 1,
         when others => 0);

   function Evaluate
     (Plan     : Improve.Model.Plan_Revision;
      Current  : Improve.Source.Selection;
      Settings : Improve.Config.Settings;
      Task_Id  : String := "";
      Previously_Verified : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector) return Report is
      Result : Report;
      Current_Findings : constant Improve.Model.Finding_Vectors.Vector :=
        Improve.Findings.Normalize
          (Current, Minimum_Severity => Ada_Quality.Types.Info, Allow_Investigation => True,
           Maximum_Findings => Settings.Maximum_Assessment_Findings,
           Maximum_Bytes => Settings.Maximum_Normalized_Finding_Bytes);
      Baseline_Indexes       : Finding_Index_Maps.Map;
      Legacy_Indexes         : Finding_Index_Maps.Map;
      Ambiguous_Baselines    : String_Sets.Set;
      Baseline_Exact         : String_Sets.Set;
      Current_Exact          : String_Sets.Set;
      Current_Raw_Exact      : String_Sets.Set;
      Current_Semantic_Pairs : String_Sets.Set;
      Semantic_Counts        : Count_Maps.Map;
      Previously_Verified_Ids : String_Sets.Set;

      function Complete_Project_Outcome return Improve.Model.Quality_Outcome is
         Inconclusive : Boolean := False;
      begin
         for Evidence of Current.Assessment.Results loop
            if Evidence.Execution = Succeeded and then Evidence.Compliance = Violation then
               return Improve.Model.Still_Failing;
            elsif Evidence.Execution = Failed and then Evidence.Compliance = Violation then
               return Improve.Model.Still_Failing;
            elsif Evidence.Execution /= Not_Applicable and then
              not (Evidence.Execution = Succeeded and then Evidence.Compliance = Pass)
            then
               Inconclusive := True;
            end if;
         end loop;
         return (if Inconclusive then Improve.Model.Inconclusive else Improve.Model.Verified);
      end Complete_Project_Outcome;

      procedure Set_Complete_Outcomes is
      begin
         if Task_Id = "" then
            Result.Project_Outcome := Complete_Project_Outcome;
            if Result.New_Critical > 0 then Result.Project_Outcome := Improve.Model.Regressed; end if;
         end if;
      end Set_Complete_Outcomes;
   begin
      Result.Plan_Id := Plan.Plan_Id;
      Result.Baseline_Run := Plan.Baseline.Run_Id;
      Result.Verification_Run := Current.Baseline.Run_Id;
      for Index in 1 .. Natural (Plan.Findings.Length) loop
         declare
            Finding    : Improve.Model.Finding_Reference renames Plan.Findings (Index);
            Fingerprint : constant String := To_String (Finding.Fingerprint);
            Identity    : constant String := Improve.Model.Finding_Key (Finding);
         begin
            if Baseline_Indexes.Contains (Identity) then
               raise Data_Error with "plan contains a duplicate canonical finding identity";
            end if;
            Baseline_Indexes.Insert (Identity, Index);
            if Legacy_Indexes.Contains (Fingerprint) then
               Ambiguous_Baselines.Include (Fingerprint);
            else
               Legacy_Indexes.Insert (Fingerprint, Index);
            end if;
            Baseline_Exact.Include (Exact_Key (Finding.Indicator, Finding.Fingerprint));
         end;
      end loop;
      for Finding of Current_Findings loop
         declare
            Semantic : constant String := Semantic_Key (Finding);
            Pair     : constant String := Semantic_Pair (Semantic, Finding.Fingerprint);
         begin
            Current_Exact.Include (Exact_Key (Finding.Indicator, Finding.Fingerprint));
            if not Current_Semantic_Pairs.Contains (Pair) then
               Current_Semantic_Pairs.Insert (Pair);
               Semantic_Counts.Include
                 (Semantic,
                  (if Semantic_Counts.Contains (Semantic)
                   then Semantic_Counts.Element (Semantic) + 1
                   else 1));
            end if;
         end;
      end loop;
      for Evidence of Current.Assessment.Results loop
         for Finding of Evidence.Findings loop
            Current_Raw_Exact.Include (Exact_Key (Finding.Indicator, Finding.Fingerprint));
         end loop;
      end loop;
      for Identity of Previously_Verified loop
         Previously_Verified_Ids.Include (To_String (Identity));
      end loop;
      if Current.Project.Id /= Plan.Project.Id then
         raise Data_Error with "verification assessment belongs to another project";
      elsif Settings.Require_Fresh_Measurement and then Current.Baseline.Run_Id <= Plan.Baseline.Run_Id then
         Result.Outcome := Improve.Model.Inconclusive;
         Result.Explanation := To_Unbounded_String ("verification requires a completed assessment newer than baseline");
         Add_Inconclusive_Tasks (Plan, Task_Id, To_String (Result.Explanation), Result);
         if Task_Id = "" then
            Result.Plan_Outcome := Improve.Model.Inconclusive;
            Result.Project_Outcome := Improve.Model.Inconclusive;
         end if;
         return Result;
      elsif Settings.Require_Same_Policy and then Current.Baseline.Policy_Id /= Plan.Baseline.Policy_Id then
         Result.Outcome := Improve.Model.Inconclusive;
         Result.Explanation := To_Unbounded_String
           ("quality policy changed; original acceptance intent is not comparable");
         Add_Inconclusive_Tasks (Plan, Task_Id, To_String (Result.Explanation), Result);
         if Task_Id = "" then
            Result.Plan_Outcome := Improve.Model.Inconclusive;
            Result.Project_Outcome := Improve.Model.Inconclusive;
         end if;
         return Result;
      elsif Settings.Require_Same_Toolchain and then Current.Baseline.Toolchain_Id /= Plan.Baseline.Toolchain_Id then
         Result.Outcome := Improve.Model.Inconclusive;
         Result.Explanation := To_Unbounded_String ("toolchain changed and equivalence is required");
         Add_Inconclusive_Tasks (Plan, Task_Id, To_String (Result.Explanation), Result);
         if Task_Id = "" then
            Result.Plan_Outcome := Improve.Model.Inconclusive;
            Result.Project_Outcome := Improve.Model.Inconclusive;
         end if;
         return Result;
      end if;
      Result.Comparable := True;
      Result.Outcome := Improve.Model.Verified;
      for Spec of Plan.Tasks loop
         if Task_Id = "" or else To_String (Spec.Id) = Task_Id then
            declare
               Item         : Task_Result;
               Outstanding  : Natural := 0;
               Inconclusive : Natural := 0;
               Task_Semantic_Matches : Count_Maps.Map;
            begin
               Item.Task_Id := Spec.Id;
               Item.Total := Natural (Spec.Finding_Keys.Length);
               for Key of Spec.Finding_Keys loop
                  declare
                     Original : constant Improve.Model.Finding_Reference :=
                       Baseline_Finding
                         (Plan, Baseline_Indexes, Legacy_Indexes, Ambiguous_Baselines, Key);
                     Semantic : constant String := Semantic_Key (Original);
                  begin
                     if Current_Semantic_Pairs.Contains
                       (Semantic_Pair (Semantic, Original.Fingerprint))
                     then
                        Task_Semantic_Matches.Include
                          (Semantic,
                           (if Task_Semantic_Matches.Contains (Semantic)
                            then Task_Semantic_Matches.Element (Semantic) + 1
                            else 1));
                     end if;
                  end;
               end loop;
               for Key of Spec.Finding_Keys loop
                  case State_Of
                    (Baseline_Finding
                       (Plan, Baseline_Indexes, Legacy_Indexes, Ambiguous_Baselines, Key), Current,
                     Current_Exact, Current_Raw_Exact, Semantic_Counts, Task_Semantic_Matches)
                  is
                     when Outstanding_Evidence => Outstanding := Outstanding + 1;
                     when Inconclusive_Evidence => Inconclusive := Inconclusive + 1;
                     when Resolved_Evidence => null;
                  end case;
               end loop;
               Item.Matched := Outstanding;
               if Item.Total = 0 then
                  Item.Outcome := Improve.Model.Inconclusive;
                  Item.Explanation := To_Unbounded_String ("task has no traceable finding requirement");
               elsif Inconclusive > 0 then
                  Item.Outcome := Improve.Model.Inconclusive;
                  Item.Explanation := To_Unbounded_String
                    ("current evidence cannot establish the disposition of every linked deficiency");
               elsif Outstanding = 0 then
                  Item.Outcome := Improve.Model.Verified;
                  Item.Explanation := To_Unbounded_String
                    ("all linked deficiencies are absent from comparable evidence");
               elsif Outstanding < Item.Total then
                  Item.Outcome := Improve.Model.Partially_Resolved;
                  Item.Explanation := To_Unbounded_String ("some linked deficiencies remain");
               else
                  Item.Outcome := Improve.Model.Still_Failing;
                  Item.Explanation := To_Unbounded_String ("all linked deficiencies remain in the assessment");
               end if;
               if Item.Outcome in Improve.Model.Still_Failing | Improve.Model.Partially_Resolved and then
                 Previously_Verified_Ids.Contains (To_String (Spec.Id))
               then
                  Item.Outcome := Improve.Model.Regressed;
                  Item.Explanation := To_Unbounded_String
                    ("a deficiency previously verified as resolved is present again");
               end if;
               Result.Tasks.Append (Item);
               if Precedence (Item.Outcome) > Precedence (Result.Outcome) then
                  Result.Outcome := Item.Outcome;
               end if;
            end;
         end if;
      end loop;
      if Result.Tasks.Is_Empty then raise Argument_Error with "task does not belong to plan: " & Task_Id; end if;
      if Settings.Require_No_New_Critical then
         for Finding of Current_Findings loop
            if Finding.Level = Critical then
               if not Baseline_Exact.Contains (Exact_Key (Finding.Indicator, Finding.Fingerprint)) then
                  Result.New_Critical := Result.New_Critical + 1;
               end if;
            end if;
         end loop;
      end if;
      if Task_Id = "" then Result.Plan_Outcome := Result.Outcome; end if;
      if Result.New_Critical > 0 then
         Result.Outcome := Improve.Model.Regressed;
         Result.Explanation := To_Unbounded_String
           ("verification evidence contains a new critical quality regression");
      else
         Result.Explanation := To_Unbounded_String ("evaluated against completed assessment evidence");
      end if;
      Set_Complete_Outcomes;
      return Result;
   end Evaluate;
end Improve.Verification;
