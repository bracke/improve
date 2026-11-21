with Model_Runner.Framework.Stores;

package body Improve.Harness_States is
   use Ada.Strings.Unbounded;
   package Tasks renames Model_Runner.Framework.Tasks;
   use type Tasks.Core_State;

   function Parse_Core (Value : String) return State is
   begin
      for Item in Tasks.Core_State loop
         if Value = Tasks.Image (Item) then
            return
              (Known_Flag => True, Core => Item, Raw_State => To_Unbounded_String (Value),
               Origin => Built_In_Origin);
         end if;
      end loop;
      return
        (Known_Flag => False, Core => Tasks.Candidate, Raw_State => To_Unbounded_String (Value),
         Origin => Unknown_Origin);
   end Parse_Core;

   function Resolve
     (Store     : Model_Runner.Framework.Stores.Store;
      Raw_State : String) return State is
      Result : State := Parse_Core (Tasks.Counts_As (Store, Raw_State));
   begin
      Result.Raw_State := To_Unbounded_String (Raw_State);
      if Result.Known_Flag then
         Result.Origin := Resolved_Origin;
      end if;
      return Result;
   end Resolve;

   function Restore (Raw_State, Core_State : String) return State is
      Result : State := Parse_Core (Core_State);
   begin
      Result.Raw_State := To_Unbounded_String (Raw_State);
      if Result.Known_Flag then
         Result.Origin := Persisted_Origin;
      end if;
      return Result;
   end Restore;

   function Is_Known (Value : State) return Boolean is (Value.Known_Flag);

   function Core_Value (Value : State) return Tasks.Core_State is (Value.Core);

   function Image (Value : State) return String is
     (if Value.Known_Flag then Tasks.Image (Value.Core) else "");

   function Consistent (Raw_State : String; Value : State) return Boolean is
      Built_In : constant State := Parse_Core (Raw_State);
   begin
      return
        Raw_State /= "" and then Value.Known_Flag and then
        To_String (Value.Raw_State) = Raw_State and then
        (not Built_In.Known_Flag or else Built_In.Core = Value.Core);
   end Consistent;

   function Authoritative_For_Write (Value : State) return Boolean is
     (Value.Known_Flag and then Value.Origin in Built_In_Origin | Resolved_Origin);
end Improve.Harness_States;
