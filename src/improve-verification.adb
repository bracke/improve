with Improve.Findings;
with Ada_Quality.Types;

package body Improve.Verification is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Improve.Model.Quality_Outcome;

   type Evidence_State is (Resolved_Evidence, Outstanding_Evidence, Inconclusive_Evidence);

   function Contract_Fingerprint (Item : Improve.Model.Task_Specification) return String is
      Material : Ada.Strings.Unbounded.Unbounded_String;

      procedure Add (Value : String) is
      begin
         Append (Material, Natural'Image (Value'Length));
         Append (Material, ":" & Value & ASCII.LF);
      end Add;
   begin
      Add (To_String (Item.Title));
      Add (To_String (Item.Category));
      Add (Improve.Model.Image (Item.Task_Priority));
      Add (To_String (Item.Goal));
      Add (To_String (Item.Problem));
      Add (To_String (Item.Evidence));
      for Value of Item.Relevant_Files loop Add (To_String (Value)); end loop;
      Add (To_String (Item.Scope));
      Add (To_String (Item.Out_Of_Scope));
      Add (To_String (Item.Requirements));
      Add (To_String (Item.Acceptance));
      Add (To_String (Item.Verification));
      for Value of Item.Dependencies loop Add (To_String (Value)); end loop;
      for Value of Item.Finding_Keys loop Add (To_String (Value)); end loop;
      Add (Natural'Image (Item.Confidence));
      Add (Boolean'Image (Item.Requires_Review));
      Add (Improve.Model.Image (Item.Kind));
      return Stable_Digest (To_String (Material));
   end Contract_Fingerprint;

   function Was_Verified
     (Task_Id : Ada.Strings.Unbounded.Unbounded_String;
      Values  : Improve.Model.UString_Vectors.Vector) return Boolean is
   begin
      for Value of Values loop
         if Value = Task_Id then return True; end if;
      end loop;
      return False;
   end Was_Verified;

   function Baseline_Finding
     (Plan : Improve.Model.Plan_Revision;
      Key  : Ada.Strings.Unbounded.Unbounded_String) return Improve.Model.Finding_Reference is
      Found : Natural := 0;
      Value : Improve.Model.Finding_Reference;
   begin
      for Finding of Plan.Findings loop
         if Finding.Fingerprint = Key then
            Found := Found + 1;
            Value := Finding;
         end if;
      end loop;
      if Found = 0 then
         raise Data_Error with "task references an unknown baseline finding";
      elsif Found > 1 then
         raise Data_Error with "task finding identity is ambiguous within its plan";
      end if;
      return Value;
   end Baseline_Finding;

   function State_Of
     (Original : Improve.Model.Finding_Reference;
      Current  : Improve.Source.Selection;
      Findings : Improve.Model.Finding_Vectors.Vector;
      Task_Keys : Improve.Model.UString_Vectors.Vector) return Evidence_State is
      Result : constant Indicator_Result := Current.Assessment.Results
        (Current.Assessment.Results.First_Index + Indicator_Id'Pos (Original.Indicator));
   begin
      if Result.Indicator /= Original.Indicator then
         raise Data_Error with "verification indicator registry order is inconsistent";
      end if;
      if Result.Execution = Succeeded and then Result.Compliance = Pass then
         return Resolved_Evidence;
      elsif Result.Execution = Succeeded and then Result.Compliance = Violation then
         if Original.Indicator_Level then return Outstanding_Evidence; end if;
         for Finding of Findings loop
            if Finding.Indicator = Original.Indicator and then Finding.Fingerprint = Original.Fingerprint then
               return Outstanding_Evidence;
            end if;
         end loop;
         for Finding of Findings loop
            if Finding.Indicator = Original.Indicator and then Finding.Rule = Original.Rule and then
              Finding.Semantic_Subject = Original.Semantic_Subject
            then
               if not Task_Keys.Contains (Finding.Fingerprint) then return Inconclusive_Evidence; end if;
            end if;
         end loop;
         return Resolved_Evidence;
      elsif Result.Execution = Failed and then Result.Compliance = Violation then
         if Original.Indicator_Level then return Outstanding_Evidence; end if;
         for Finding of Result.Findings loop
            if Finding.Fingerprint = Original.Fingerprint then return Outstanding_Evidence; end if;
         end loop;
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
          (Current, Minimum_Severity => Ada_Quality.Types.Info, Allow_Investigation => True);

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
            begin
               Item.Task_Id := Spec.Id;
               Item.Total := Natural (Spec.Finding_Keys.Length);
               for Key of Spec.Finding_Keys loop
                  case State_Of (Baseline_Finding (Plan, Key), Current, Current_Findings, Spec.Finding_Keys) is
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
                 Was_Verified (Spec.Id, Previously_Verified)
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
               declare Known : Boolean := False; begin
                  for Original of Plan.Findings loop
                     if Original.Indicator = Finding.Indicator and then Original.Fingerprint = Finding.Fingerprint then
                        Known := True;
                        exit;
                     end if;
                  end loop;
                  if not Known then Result.New_Critical := Result.New_Critical + 1; end if;
               end;
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
