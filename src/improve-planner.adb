with Ada.Calendar;
with Ada.Containers;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Ada_Quality.Checks;
with Ada_Quality.Types;
with Improve.Rules;

package body Improve.Planner is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Indicator_Id;
   use type Ada_Quality.Types.Severity;
   use type Improve.Model.Candidate_Kind;

   type Group is record
      Key      : Unbounded_String;
      Findings : Improve.Model.Finding_Vectors.Vector;
   end record;

   package Group_Vectors is new Ada.Containers.Vectors (Positive, Group);

   package Group_Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Configuration_Fingerprint (Settings : Improve.Config.Settings) return String is
     (Stable_Digest
        (Improve.Config.Severity_Level'Image (Settings.Minimum_Severity) & "|" &
         Positive'Image (Settings.Maximum_Assessment_Findings) & "|" &
         Positive'Image (Settings.Maximum_Assessment_Bytes) & "|" &
         Positive'Image (Settings.Maximum_Tasks_Per_Plan) & "|" &
         Positive'Image (Settings.Maximum_Findings_Per_Task) & "|" &
         Boolean_Image (Settings.Allow_Investigation_Tasks) & "|" &
         Boolean_Image (Settings.Require_Review)));

   function Group_Key (Item : Improve.Model.Finding_Reference) return String is
     (Improve.Model.Canonical_Key
        ([To_Unbounded_String (Ada_Quality.Types.Image (Item.Indicator)),
          To_Unbounded_String (Improve.Model.Image (Item.Kind)), Item.Rule, Item.Semantic_Subject]));

   function Priority_Of (Item : Improve.Model.Finding_Reference) return Improve.Model.Priority is
   begin
      if Item.Level = Ada_Quality.Types.Critical or else
        (Item.Indicator in Ada_Quality.Types.SEC_01 .. Ada_Quality.Types.SEC_03 and then
         Item.Level >= Ada_Quality.Types.High)
      then
         return Improve.Model.Critical_Priority;
      elsif Item.Level >= Ada_Quality.Types.High or else
        Item.Indicator in Ada_Quality.Types.BLD_01 .. Ada_Quality.Types.BLD_04 |
          Ada_Quality.Types.DEP_01 .. Ada_Quality.Types.DEP_03 |
          Ada_Quality.Types.REL_01 .. Ada_Quality.Types.REL_04
      then
         return Improve.Model.High_Priority;
      elsif Item.Kind /= Improve.Model.Remediation_Candidate or else Item.Level <= Ada_Quality.Types.Low then
         return Improve.Model.Low_Priority;
      else
         return Improve.Model.Normal_Priority;
      end if;
   end Priority_Of;

   function Stronger
     (Left, Right : Improve.Model.Priority) return Improve.Model.Priority is
     (if Improve.Model.Priority'Pos (Left) < Improve.Model.Priority'Pos (Right) then Left else Right);

   function Make_Task
     (Item     : Group;
      Sequence : Positive;
      Settings : Improve.Config.Settings) return Improve.Model.Task_Specification is
      First    : constant Improve.Model.Finding_Reference := Item.Findings.First_Element;
      Strategy : constant Improve.Rules.Remediation_Strategy := Improve.Rules.Strategy_For (First.Indicator);
      Aggregate_Coverage : constant Boolean :=
        First.Indicator = Ada_Quality.Types.TST_03 and then First.Indicator_Level;
      Kind : constant Improve.Model.Candidate_Kind :=
        (if Aggregate_Coverage then Improve.Model.Investigation_Candidate else First.Kind);
      Identity : constant String := "IMP-DRAFT-" & Stable_Digest (To_String (Item.Key) & Positive'Image (Sequence));
      Result   : Improve.Model.Task_Specification;
      Priority : Improve.Model.Priority := Priority_Of (First);
      Files    : String_Sets.Set;
   begin
      Result.Id := To_Unbounded_String (Identity);
      Result.Title :=
        (if Aggregate_Coverage then To_Unbounded_String ("Investigate missing coverage evidence") else Strategy.Title);
      Result.Category := To_Unbounded_String
        ((if Kind = Improve.Model.Remediation_Candidate then Improve.Rules.Image (Strategy.Kind) else "investigation"));
      Result.Goal :=
        (if Aggregate_Coverage
         then To_Unbounded_String ("Locate source-level coverage evidence before proposing focused test changes.")
         else Strategy.Goal);
      Result.Problem := To_Unbounded_String
        ("Ada Quality reported an " & Ada_Quality.Types.Image (First.Indicator) &
         " deficiency. Full diagnostic text remains untrusted evidence in Improve state.");
      Result.Scope :=
        (if Length (First.Relative_Path) > 0
         then To_Unbounded_String
           ("Limit changes to " & To_String (First.Relative_Path) & " and directly related tests.")
         else To_Unbounded_String ("Limit work to the evidenced " & Ada_Quality.Types.Image (First.Indicator) &
              " requirement; do not invent source-level defects."));
      Result.Out_Of_Scope := To_Unbounded_String
        ("Do not disable quality checks, broaden permissions, or change unrelated project behavior.");
      Result.Requirements := To_Unbounded_String
        ("Preserve the assessment evidence and address every linked finding without treating hypotheses as facts.");
      Result.Acceptance :=
        (if Aggregate_Coverage
         then To_Unbounded_String
           ("Identify reproducible file- or unit-level coverage evidence and document any justified follow-up tasks.")
         else Strategy.Acceptance);
      Result.Verification := Strategy.Verification;
      Result.Confidence := (if Kind = Improve.Model.Remediation_Candidate then 85 else 50);
      Result.Requires_Review := Settings.Require_Review;
      Result.Kind := Kind;
      for Finding of Item.Findings loop
         Result.Finding_Keys.Append (To_Unbounded_String (Improve.Model.Finding_Key (Finding)));
         if Length (Finding.Relative_Path) > 0 and then
           not Files.Contains (To_String (Finding.Relative_Path))
         then
            Files.Insert (To_String (Finding.Relative_Path));
            Result.Relevant_Files.Append (Finding.Relative_Path);
         end if;
         Priority := Stronger (Priority, Priority_Of (Finding));
      end loop;
      Result.Evidence := To_Unbounded_String
        (Natural'Image (Natural (Item.Findings.Length)) &
         " linked finding reference(s) are retained in the Improve-owned plan; diagnostic text is not executable.");
      Result.Task_Priority := Priority;
      return Result;
   end Make_Task;

   function Generate
     (Selected : Improve.Source.Selection;
      Findings : Improve.Model.Finding_Vectors.Vector;
      Settings : Improve.Config.Settings;
      Working_Source_Id : String := "") return Improve.Model.Plan_Revision is
      Groups : Group_Vectors.Vector;
      Group_Indexes : Group_Index_Maps.Map;
      Result : Improve.Model.Plan_Revision;
      Config_Id : constant String := Configuration_Fingerprint (Settings);
      Current_Measured_Source : constant String :=
        Ada_Quality.Checks.Source_Fingerprint (To_String (Selected.Project.Path));
   begin
      if Current_Measured_Source /= To_String (Selected.Baseline.Source_Id) then
         raise Data_Error with
           "current project source does not match the selected assessment; remeasure before planning";
      end if;
      for Finding of Findings loop
         declare
            Key : constant String := Group_Key (Finding);
         begin
            if Group_Indexes.Contains (Key) and then
              Groups (Group_Indexes.Element (Key)).Findings.Length <
                Ada.Containers.Count_Type (Settings.Maximum_Findings_Per_Task)
            then
               Groups (Group_Indexes.Element (Key)).Findings.Append (Finding);
            else
               if Groups.Length >= Ada.Containers.Count_Type (Settings.Maximum_Tasks_Per_Plan) then
                  raise Data_Error with "planned task count exceeds planning.maximum_tasks_per_plan";
               end if;
               declare New_Group : Group; begin
                  New_Group.Key := To_Unbounded_String (Key);
                  New_Group.Findings.Append (Finding);
                  Groups.Append (New_Group);
                  Group_Indexes.Include (Key, Groups.Last_Index);
               end;
            end if;
         end;
      end loop;
      Result.Project := Selected.Project;
      Result.Baseline := Selected.Baseline;
      Result.Working_Source_Id := To_Unbounded_String
        (if Working_Source_Id = "" then
           Improve.Source.Working_Fingerprint (To_String (Selected.Project.Path))
         else Working_Source_Id);
      Result.Planner_Id := To_Unbounded_String (Planner_Version & ":" & Config_Id);
      Result.Created_At := Ada.Calendar.Time_Of (1970, 1, 1);
      Result.Findings := Findings;
      Result.Review_Status := To_Unbounded_String (if Settings.Require_Review then "pending" else "not-required");
      for Index in 1 .. Natural (Groups.Length) loop
         Result.Tasks.Append (Make_Task (Groups (Index), Index, Settings));
      end loop;
      declare
         Material : Unbounded_String;

         procedure Add (Name, Value : String) is
         begin
            Append (Material, Natural'Image (Name'Length) & ":" & Name);
            Append (Material, Natural'Image (Value'Length) & ":" & Value);
         end Add;
      begin
         Add ("planner", Planner_Version);
         Add ("configuration", Config_Id);
         Add ("quality_database", To_String (Selected.Project.Database_Id));
         Add ("project_id", Positive'Image (Selected.Project.Id));
         Add ("project_path", To_String (Selected.Project.Path));
         Add ("assessment_run", Positive'Image (Selected.Assessment.Run.Id));
         Add ("source", To_String (Selected.Baseline.Source_Id));
         Add ("working_source", To_String (Result.Working_Source_Id));
         Add ("policy", To_String (Selected.Baseline.Policy_Id));
         Add ("toolchain", To_String (Selected.Baseline.Toolchain_Id));
         Add ("assessment", To_String (Selected.Baseline.Evidence_Id));
         Add ("finding_count", Natural'Image (Natural (Result.Findings.Length)));
         for Finding of Result.Findings loop
            Add ("finding.project", Positive'Image (Finding.Project_Id));
            Add ("finding.run", Positive'Image (Finding.Run_Id));
            Add ("finding.indicator", Ada_Quality.Types.Image (Finding.Indicator));
            Add ("finding.rule", To_String (Finding.Rule));
            Add ("finding.severity", Ada_Quality.Types.Severity'Image (Finding.Level));
            Add ("finding.path", To_String (Finding.Relative_Path));
            Add ("finding.line", Natural'Image (Finding.Line));
            Add ("finding.fingerprint", To_String (Finding.Fingerprint));
            Add ("finding.subject", To_String (Finding.Semantic_Subject));
            Add ("finding.message", To_String (Finding.Message));
            Add ("finding.evidence", To_String (Finding.Evidence));
            Add ("finding.kind", Improve.Model.Image (Finding.Kind));
            Add ("finding.indicator_level", Boolean'Image (Finding.Indicator_Level));
         end loop;
         Add ("task_count", Natural'Image (Natural (Result.Tasks.Length)));
         for Spec of Result.Tasks loop
            Add ("task.id", To_String (Spec.Id));
            Add ("task.contract", Improve.Model.Task_Contract_Fingerprint (Spec));
         end loop;
         Result.Fingerprint := To_Unbounded_String (Stable_Digest (To_String (Material)));
         Result.Plan_Id := To_Unbounded_String ("PLAN-DRAFT-" & To_String (Result.Fingerprint));
      end;
      Improve.Model.Validate (Result);
      return Result;
   end Generate;
end Improve.Planner;
