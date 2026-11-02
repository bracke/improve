with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;

--  Public remediation domain records, independent of storage and presentation.
package Improve.Model is
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

   type Assessment_Baseline is record
      Project_Id   : Positive;
      Run_Id       : Positive;
      Source_Id    : UString;
      Policy_Id    : UString;
      Toolchain_Id : UString;
      Snapshot_Id  : UString;
   end record;
   --  Immutable provenance of the completed assessment used by one revision.

   type Candidate_Kind is (Remediation_Candidate, Investigation_Candidate, Diagnostic_Candidate);
   --  Whether evidence establishes implementation work, investigation work, or only a diagnostic prerequisite.

   type Priority is (Critical_Priority, High_Priority, Normal_Priority, Low_Priority);
   --  Deterministic task ordering, highest first.

   function Image (Item : Candidate_Kind) return String;
   --  Return the stable lowercase candidate spelling.

   function Image (Item : Priority) return String;
   --  Return the stable lowercase priority spelling.

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
end Improve.Model;

