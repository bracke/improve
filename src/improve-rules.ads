with Ada.Strings.Unbounded;
with Ada_Quality.Types;

--  Complete typed registry mapping every Ada Quality indicator to remediation semantics.
package Improve.Rules is
   --  Complete typed remediation-strategy registry for every Ada Quality indicator.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized strategy text.

   type Strategy_Kind is
     (Structural_Repair,
      Build_Repair,
      Test_Repair,
      Coverage_Improvement,
      Source_Refactoring,
      Documentation_Repair,
      Dependency_Repair,
      Security_Repair,
      Release_Repair,
      Proof_Repair,
      Investigation);
   --  Stable planning strategy classes.
   --  @enum Structural_Repair Project structure repair.
   --  @enum Build_Repair Compilation or validation repair.
   --  @enum Test_Repair Test execution or registration repair.
   --  @enum Coverage_Improvement Evidence-backed coverage work.
   --  @enum Source_Refactoring Source quality refactoring.
   --  @enum Documentation_Repair Documentation repair.
   --  @enum Dependency_Repair Dependency solution repair.
   --  @enum Security_Repair Security-sensitive repair.
   --  @enum Release_Repair Release metadata or process repair.
   --  @enum Proof_Repair SPARK proof repair.
   --  @enum Investigation Work to establish missing evidence or scope.

   type Remediation_Strategy is record
      Indicator    : Ada_Quality.Types.Indicator_Id;
      Kind         : Strategy_Kind;
      Title        : UString;
      Goal         : UString;
      Acceptance   : UString;
      Verification : UString;
   end record;
   --  Deterministic strategy metadata for one indicator.
   --  @field Indicator Ada Quality indicator.
   --  @field Kind Planning strategy class.
   --  @field Title Default task title.
   --  @field Goal Default remediation goal.
   --  @field Acceptance Required completion criteria.
   --  @field Verification Required measurement criterion.

   function Strategy_For (Indicator : Ada_Quality.Types.Indicator_Id) return Remediation_Strategy;
   --  Return the registered strategy; every value of Indicator_Id is covered.
   --  @param Indicator Ada Quality indicator.
   --  @return Strategy metadata.

   function Image (Kind : Strategy_Kind) return String;
   --  Return the stable lowercase strategy spelling.
   --  @param Kind Strategy class.
   --  @return Stable lowercase spelling.
end Improve.Rules;

