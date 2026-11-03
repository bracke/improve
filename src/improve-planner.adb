with Ada.Calendar;
with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Checks;
with Ada_Quality.Types;
with Improve.Dependencies;
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

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Configuration_Fingerprint (Settings : Improve.Config.Settings) return String is
     (Stable_Digest
        (Improve.Config.Severity_Level'Image (Settings.Minimum_Severity) & "|" &
         Positive'Image (Settings.Maximum_Tasks_Per_Plan) & "|" &
         Positive'Image (Settings.Maximum_Findings_Per_Task) & "|" &
         Boolean_Image (Settings.Allow_Investigation_Tasks) & "|" &
         Boolean_Image (Settings.Require_Review)));

   function Group_Key (Item : Improve.Model.Finding_Reference) return String is
     (Ada_Quality.Types.Image (Item.Indicator) & "|" & Improve.Model.Image (Item.Kind) & "|" &
      To_String (Item.Rule) & "|" & To_String (Item.Semantic_Subject));

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
      Evidence : Unbounded_String;
      Priority : Improve.Model.Priority := Priority_Of (First);
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
      Result.Problem := First.Message;
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
         if Length (Evidence) > 0 then Append (Evidence, Character'Val (10)); end if;
         Append
           (Evidence,
            Ada_Quality.Types.Image (Finding.Indicator) & " [" & To_String (Finding.Fingerprint) & "]: " &
            To_String (Finding.Message));
         Result.Finding_Keys.Append (Finding.Fingerprint);
         if Length (Finding.Relative_Path) > 0 and then
           (Result.Relevant_Files.Is_Empty or else
            Result.Relevant_Files.Last_Element /= Finding.Relative_Path)
         then
            Result.Relevant_Files.Append (Finding.Relative_Path);
         end if;
         Priority := Stronger (Priority, Priority_Of (Finding));
      end loop;
      Result.Evidence := Evidence;
      Result.Task_Priority := Priority;
      return Result;
   end Make_Task;

   function Generate
     (Selected : Improve.Source.Selection;
      Findings : Improve.Model.Finding_Vectors.Vector;
      Settings : Improve.Config.Settings) return Improve.Model.Plan_Revision is
      Groups : Group_Vectors.Vector;
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
            Key   : constant String := Group_Key (Finding);
            Added : Boolean := False;
         begin
            for Index in 1 .. Natural (Groups.Length) loop
               if To_String (Groups (Index).Key) = Key and then
                 Groups (Index).Findings.Length < Ada.Containers.Count_Type (Settings.Maximum_Findings_Per_Task)
               then
                  Groups (Index).Findings.Append (Finding);
                  Added := True;
                  exit;
               end if;
            end loop;
            if not Added then
               declare New_Group : Group; begin
                  New_Group.Key := To_Unbounded_String (Key);
                  New_Group.Findings.Append (Finding);
                  Groups.Append (New_Group);
               end;
            end if;
         end;
      end loop;
      if Groups.Length > Ada.Containers.Count_Type (Settings.Maximum_Tasks_Per_Plan) then
         raise Data_Error with "planned task count exceeds planning.maximum_tasks_per_plan";
      end if;
      Result.Project := Selected.Project;
      Result.Baseline := Selected.Baseline;
      Result.Working_Source_Id := To_Unbounded_String
        (Improve.Source.Working_Fingerprint (To_String (Selected.Project.Path)));
      Result.Planner_Id := To_Unbounded_String (Planner_Version & ":" & Config_Id);
      Result.Created_At := Ada.Calendar.Time_Of (1970, 1, 1);
      Result.Findings := Findings;
      Result.Review_Status := To_Unbounded_String (if Settings.Require_Review then "pending" else "not-required");
      for Index in 1 .. Natural (Groups.Length) loop
         Result.Tasks.Append (Make_Task (Groups (Index), Index, Settings));
      end loop;
      Improve.Dependencies.Validate (Result.Tasks);
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
         Add ("snapshot", To_String (Selected.Baseline.Snapshot_Id));
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
      return Result;
   end Generate;
end Improve.Planner;
