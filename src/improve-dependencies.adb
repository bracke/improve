with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

package body Improve.Dependencies is
   use Ada.Strings.Unbounded;

   package Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Positive,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   package Index_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   type Count_Array is array (Natural range <>) of Natural;
   type Adjacency_Array is array (Natural range <>) of Index_Vectors.Vector;

   procedure Validate (Tasks : Improve.Model.Task_Vectors.Vector) is
      Count      : constant Natural := Natural (Tasks.Length);
      Indexes    : Index_Maps.Map;
      Remaining  : Count_Array (1 .. Count) := [others => 0];
      Dependents : Adjacency_Array (1 .. Count);
      Ready      : Index_Vectors.Vector;
      Head       : Natural := 1;
      Visited    : Natural := 0;
   begin
      for Index in 1 .. Count loop
         declare
            Identity : constant String := To_String (Tasks (Index).Id);
         begin
            if Identity = "" then
               raise Data_Error with "task identity must not be empty";
            elsif Indexes.Contains (Identity) then
               raise Data_Error with "duplicate task identity " & Identity;
            end if;
            Indexes.Insert (Identity, Index);
         end;
      end loop;

      for Index in 1 .. Count loop
         declare
            Seen : String_Sets.Set;
         begin
            for Dependency of Tasks (Index).Dependencies loop
               declare
                  Name : constant String := To_String (Dependency);
               begin
                  if Seen.Contains (Name) then
                     raise Data_Error with
                       "duplicate dependency edge on " & To_String (Tasks (Index).Id);
                  elsif not Indexes.Contains (Name) then
                     raise Data_Error with "unknown task dependency " & Name;
                  elsif Indexes.Element (Name) = Index then
                     raise Data_Error with
                       "task cannot depend on itself: " & To_String (Tasks (Index).Id);
                  end if;
                  Seen.Insert (Name);
                  Remaining (Index) := Remaining (Index) + 1;
                  Dependents (Indexes.Element (Name)).Append (Index);
               end;
            end loop;
         end;
      end loop;

      for Index in 1 .. Count loop
         if Remaining (Index) = 0 then
            Ready.Append (Index);
         end if;
      end loop;
      while Head <= Natural (Ready.Length) loop
         declare
            Current : constant Positive := Ready (Head);
         begin
            Head := Head + 1;
            Visited := Visited + 1;
            for Dependent of Dependents (Current) loop
               Remaining (Dependent) := Remaining (Dependent) - 1;
               if Remaining (Dependent) = 0 then
                  Ready.Append (Dependent);
               end if;
            end loop;
         end;
      end loop;

      if Visited /= Count then
         for Index in 1 .. Count loop
            if Remaining (Index) > 0 then
               raise Data_Error with
                 "task dependency graph contains a cycle at " & To_String (Tasks (Index).Id);
            end if;
         end loop;
      end if;
   end Validate;
end Improve.Dependencies;
