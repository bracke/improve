with Ada.Strings.Unbounded;
with Ada_Quality.Types;

--  Complete typed registry mapping every Ada Quality indicator to remediation semantics.
package Improve.Rules is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

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

   type Remediation_Strategy is record
      Indicator    : Ada_Quality.Types.Indicator_Id;
      Kind         : Strategy_Kind;
      Title        : UString;
      Goal         : UString;
      Acceptance   : UString;
      Verification : UString;
   end record;
   --  Deterministic strategy metadata for one indicator.

   function Strategy_For (Indicator : Ada_Quality.Types.Indicator_Id) return Remediation_Strategy;
   --  Return the registered strategy; every value of Indicator_Id is covered.
   --  @param Indicator Ada Quality indicator.
   --  @return Strategy metadata.

   function Image (Kind : Strategy_Kind) return String;
   --  Return the stable lowercase strategy spelling.
end Improve.Rules;

