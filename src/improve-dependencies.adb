with Ada.Strings.Unbounded;

package body Improve.Dependencies is
   use Ada.Strings.Unbounded;

   type Visit_State is (Unvisited, Visiting, Visited);

   procedure Validate (Tasks : Improve.Model.Task_Vectors.Vector) is
      Count : constant Natural := Natural (Tasks.Length);
      type State_Array is array (Natural range <>) of Visit_State;
      State : State_Array (1 .. Count) := [others => Unvisited];

      function Index_Of (Identity : String) return Natural is
      begin
         for Index in 1 .. Count loop
            if To_String (Tasks (Index).Id) = Identity then return Index; end if;
         end loop;
         return 0;
      end Index_Of;

      procedure Visit (Index : Positive) is
      begin
         if State (Index) = Visiting then
            raise Data_Error with "task dependency graph contains a cycle at " & To_String (Tasks (Index).Id);
         elsif State (Index) = Visited then
            return;
         end if;
         State (Index) := Visiting;
         for Dependency of Tasks (Index).Dependencies loop
            declare
               Target : constant Natural := Index_Of (To_String (Dependency));
            begin
               if Target = 0 then
                  raise Data_Error with "unknown task dependency " & To_String (Dependency);
               elsif Target = Index then
                  raise Data_Error with "task cannot depend on itself: " & To_String (Tasks (Index).Id);
               end if;
               Visit (Positive (Target));
            end;
         end loop;
         State (Index) := Visited;
      end Visit;
   begin
      for Left in 1 .. Count loop
         if Length (Tasks (Left).Id) = 0 then raise Data_Error with "task identity must not be empty"; end if;
         for Right in Left + 1 .. Count loop
            if Tasks (Left).Id = Tasks (Right).Id then
               raise Data_Error with "duplicate task identity " & To_String (Tasks (Left).Id);
            end if;
         end loop;
         for First in 1 .. Natural (Tasks (Left).Dependencies.Length) loop
            for Second in First + 1 .. Natural (Tasks (Left).Dependencies.Length) loop
               if Tasks (Left).Dependencies (First) = Tasks (Left).Dependencies (Second) then
                  raise Data_Error with "duplicate dependency edge on " & To_String (Tasks (Left).Id);
               end if;
            end loop;
         end loop;
      end loop;
      for Index in 1 .. Count loop
         Visit (Index);
      end loop;
   end Validate;
end Improve.Dependencies;
