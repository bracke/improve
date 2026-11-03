with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;

--  Public remediation domain records, independent of storage and presentation.
package Improve.Model is
   --  Storage-independent remediation domain model and stable external spellings.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized UTF-8 text.

   package UString_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => UString, "=" => Ada.Strings.Unbounded."=");
   --  Ordered text values.

   type Project_Reference is record
      Id   : Positive;
      Name : UString;
      Path : UString;
   end record;
   --  Ada Quality project registry entry selected for planning.
   --  @field Id Persistent Ada Quality project identity.
   --  @field Name Unique display name.
   --  @field Path Canonical project root.

   type Assessment_Baseline is record
      Project_Id   : Positive;
      Run_Id       : Positive;
      Source_Id    : UString;
      Policy_Id    : UString;
      Toolchain_Id : UString;
      Snapshot_Id  : UString;
   end record;
   --  Immutable provenance of the completed assessment used by one revision.
   --  @field Project_Id Owning project identity.
   --  @field Run_Id Completed assessment identity.
   --  @field Source_Id Source fingerprint.
   --  @field Policy_Id Policy fingerprint.
   --  @field Toolchain_Id Toolchain fingerprint.
   --  @field Snapshot_Id Reporting snapshot identity.

   type Candidate_Kind is (Remediation_Candidate, Investigation_Candidate, Diagnostic_Candidate);
   --  Whether evidence establishes implementation work, investigation work, or only a diagnostic prerequisite.
   --  @enum Remediation_Candidate Evidence-backed implementation work.
   --  @enum Investigation_Candidate Work to establish missing scope or cause.
   --  @enum Diagnostic_Candidate Work to restore unavailable prerequisite evidence.

   type Priority is (Critical_Priority, High_Priority, Normal_Priority, Low_Priority);
   --  Deterministic task ordering, highest first.
   --  @enum Critical_Priority Release-blocking work.
   --  @enum High_Priority High-impact work.
   --  @enum Normal_Priority Ordinary remediation work.
   --  @enum Low_Priority Lower-impact investigation or repair.

   function Image (Item : Candidate_Kind) return String;
   --  Return the stable lowercase candidate spelling.
   --  @param Item Candidate kind.
   --  @return Stable lowercase spelling.

   function Image (Item : Priority) return String;
   --  Return the stable lowercase priority spelling.
   --  @param Item Priority value.
   --  @return Stable lowercase spelling.

   type Quality_Outcome is
     (Unverified, Verified, Partially_Resolved, Still_Failing, Regressed, Inconclusive, Superseded);
   --  Improve-owned evidence outcome, independent of harness task state.
   --  @enum Unverified No verification evidence has been evaluated.
   --  @enum Verified Every mandatory criterion is satisfied.
   --  @enum Partially_Resolved Some associated criteria are satisfied.
   --  @enum Still_Failing Mandatory quality criteria still fail.
   --  @enum Regressed Previously resolved quality has failed again.
   --  @enum Inconclusive Evidence cannot establish success or failure.
   --  @enum Superseded Newer valid work replaced this outcome.

   function Image (Item : Quality_Outcome) return String;
   --  Return the stable lowercase quality outcome spelling.
   --  @param Item Quality outcome.
   --  @return Stable lowercase spelling.

   type Finding_Reference is record
      Project_Id      : Positive;
      Run_Id          : Positive;
      Indicator       : Ada_Quality.Types.Indicator_Id;
      Rule            : UString;
      Level           : Ada_Quality.Types.Severity := Ada_Quality.Types.Medium;
      Relative_Path   : UString;
      Line            : Natural := 0;
      Fingerprint     : UString;
      Semantic_Subject : UString;
      Message         : UString;
      Evidence        : UString;
      Kind            : Candidate_Kind := Remediation_Candidate;
      Indicator_Level : Boolean := False;
   end record;
   --  One normalized deficiency or unavailable-evidence candidate.
   --  @field Project_Id Owning project identity.
   --  @field Run_Id Originating assessment identity.
   --  @field Indicator Owning Ada Quality indicator.
   --  @field Rule Stable diagnostic rule.
   --  @field Level Finding severity.
   --  @field Relative_Path Safe project-relative source path.
   --  @field Line One-based source line or zero.
   --  @field Fingerprint Stable Ada Quality finding identity.
   --  @field Semantic_Subject Unit, path, rule, or indicator subject.
   --  @field Message Human-readable diagnostic.
   --  @field Evidence Measurement evidence.
   --  @field Kind Candidate classification.
   --  @field Indicator_Level Whether no individual source finding exists.

   package Finding_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Finding_Reference);
   --  Deterministically ordered finding references.

   type Task_Specification is record
      Id               : UString;
      Title            : UString;
      Category         : UString;
      Task_Priority    : Priority := Normal_Priority;
      Goal             : UString;
      Problem          : UString;
      Evidence         : UString;
      Relevant_Files   : UString_Vectors.Vector;
      Scope            : UString;
      Out_Of_Scope     : UString;
      Requirements     : UString;
      Acceptance       : UString;
      Verification     : UString;
      Dependencies     : UString_Vectors.Vector;
      Finding_Keys     : UString_Vectors.Vector;
      Confidence       : Natural range 0 .. 100 := 100;
      Requires_Review  : Boolean := True;
      Kind             : Candidate_Kind := Remediation_Candidate;
   end record;
   --  Complete Improve-owned candidate work specification.
   --  @field Id Stable Improve task identity.
   --  @field Title Concise work title.
   --  @field Category Configurable harness category.
   --  @field Task_Priority Deterministic priority.
   --  @field Goal Desired remediation outcome.
   --  @field Problem Evidence-backed problem statement.
   --  @field Evidence Measurement evidence references.
   --  @field Relevant_Files Authorized project-relative files.
   --  @field Scope Required work boundary.
   --  @field Out_Of_Scope Explicit exclusions.
   --  @field Requirements Existing harness requirements when applicable.
   --  @field Acceptance Explicit completion criteria.
   --  @field Verification Independent measurement criteria.
   --  @field Dependencies Improve task prerequisites.
   --  @field Finding_Keys Linked finding fingerprints.
   --  @field Confidence Planning confidence percentage.
   --  @field Requires_Review Whether publication requires human review.
   --  @field Kind Candidate classification.

   package Task_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Task_Specification);
   --  Proposed remediation tasks in dependency order.

   type Plan_Revision is record
      Plan_Id       : UString;
      Revision      : Positive := 1;
      Project       : Project_Reference;
      Baseline      : Assessment_Baseline;
      Planner_Id    : UString;
      Created_At    : Ada.Calendar.Time := Ada.Calendar.Time_Of (1970, 1, 1);
      Findings      : Finding_Vectors.Vector;
      Tasks         : Task_Vectors.Vector;
      Fingerprint   : UString;
      Review_Status : UString;
   end record;
   --  Immutable generated plan revision.
   --  @field Plan_Id Stable logical plan identity.
   --  @field Revision Immutable revision ordinal.
   --  @field Project Target project.
   --  @field Baseline Assessment baseline.
   --  @field Planner_Id Planner configuration fingerprint.
   --  @field Created_At Revision creation time.
   --  @field Findings Normalized baseline findings.
   --  @field Tasks Proposed remediation tasks.
   --  @field Fingerprint Deterministic revision identity.
   --  @field Review_Status Review state.
end Improve.Model;
