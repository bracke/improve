with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package body Improve_Coverage_Units is
   use Ada.Strings.Unbounded;

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   function Source_Stem (Path : String) return String is
      Name : constant String := Ada.Directories.Simple_Name (Path);
   begin
      if Name'Length <= 4 or else Name (Name'Last - 3 .. Name'Last) /= ".adb" then
         raise Program_Error with "invalid inventoried Ada body path " & Path;
      end if;
      return Ada.Characters.Handling.To_Lower (Name (Name'First .. Name'Last - 4));
   end Source_Stem;

   function Owns_Subunit
     (Owner : Ada_Quality.Coverage.Production_Unit;
      Stem  : String) return Boolean is
   begin
      for Path of Owner.Subunit_Paths loop
         if Source_Stem (To_String (Path)) = Stem then
            return True;
         end if;
      end loop;
      return False;
   end Owns_Subunit;

   function Compilation_Stem
     (Unit  : Ada_Quality.Coverage.Production_Unit;
      Units : Ada_Quality.Coverage.Production_Unit_Vectors.Vector) return String is
      Current : Unbounded_String := Unit.Stem;
      Visited : String_Sets.Set;
   begin
      Visited.Insert (To_String (Current));
      for Depth in 1 .. 32 loop
         declare
            Owner : Unbounded_String;
         begin
            for Candidate of Units loop
               if Owns_Subunit (Candidate, To_String (Current)) then
                  if Length (Owner) > 0 and then Owner /= Candidate.Stem then
                     raise Program_Error with "ambiguous inventoried subunit owner " & To_String (Current);
                  end if;
                  Owner := Candidate.Stem;
               end if;
            end loop;
            if Length (Owner) = 0 then
               return To_String (Current);
            elsif Visited.Contains (To_String (Owner)) then
               raise Program_Error with "cyclic inventoried subunit ownership " & To_String (Owner);
            elsif Depth = 32 then
               raise Program_Error with "inventoried subunit nesting exceeds coverage limit";
            end if;
            Visited.Insert (To_String (Owner));
            Current := Owner;
         end;
      end loop;
      raise Program_Error with "inventoried subunit nesting exceeds coverage limit";
   end Compilation_Stem;
end Improve_Coverage_Units;
