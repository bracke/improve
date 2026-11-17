with Ada_Quality.Coverage;

--  Resolve compiler coverage objects for ordinary units and nested Ada subunits.
package Improve_Coverage_Units is
   function Compilation_Stem
     (Unit  : Ada_Quality.Coverage.Production_Unit;
      Units : Ada_Quality.Coverage.Production_Unit_Vectors.Vector) return String;
   --  Return the GNAT object stem that owns Unit's coverage records.
   --  @param Unit Inventoried production unit or subunit.
   --  @param Units Complete typed production inventory containing subunit ownership.
   --  @return Root compilation-unit object stem.
end Improve_Coverage_Units;
