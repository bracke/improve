with Ada_Quality.Coverage;

--  Resolve compiler coverage objects for ordinary units and nested Ada subunits.
package Improve_Coverage_Units is
   function Compilation_Stem
     (Unit : Ada_Quality.Coverage.Production_Unit) return String;
   --  Return the GNAT object stem that owns Unit's coverage records.
   --  @param Unit Inventoried production unit or subunit.
   --  @return Root compilation-unit object stem.
end Improve_Coverage_Units;
