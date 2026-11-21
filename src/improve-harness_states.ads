with Ada.Strings.Unbounded;
limited with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

--  Typed, provenance-aware projection of model_runner task states.
package Improve.Harness_States is
   --  Encapsulated raw/core state binding. Values can only be created from a
   --  core spelling or through model_runner's configured state mapping.

   type State is private;
   --  Raw model_runner state paired with its typed core meaning, when known.

   function Parse_Core (Value : String) return State;
   --  Parse one built-in model_runner core-state spelling.
   --  @param Value Candidate normalized core-state spelling.
   --  @return Known built-in state, or an unknown state when Value is not built in.

   function Resolve
     (Store     : Model_Runner.Framework.Stores.Store;
      Raw_State : String) return State;
   --  Resolve a raw task state through model_runner's configured mapping.
   --  @param Store Open model_runner store owning the task-state vocabulary.
   --  @param Raw_State Raw model_runner task state.
   --  @return State bound to Raw_State and its configured core meaning.

   function Is_Known (Value : State) return Boolean;
   --  Return whether a typed core meaning is available.
   --  @param Value State binding to inspect.
   --  @return True when Value carries a typed model_runner core state.

   function Core_Value
     (Value : State) return Model_Runner.Framework.Tasks.Core_State
     with Pre => Is_Known (Value);
   --  Return the typed core meaning of a known state.
   --  @param Value Known state binding to inspect.
   --  @return Typed model_runner core state carried by Value.

   function Image (Value : State) return String;
   --  Return the model_runner core spelling, or empty when unknown.
   --  @param Value State binding to render.
   --  @return Canonical core-state spelling, or an empty string when unknown.

   function Consistent (Raw_State : String; Value : State) return Boolean;
   --  Return whether Raw_State matches the binding carried by Value.
   --  @param Raw_State Raw model_runner state to compare.
   --  @param Value State binding carrying the persisted raw state.
   --  @return True when Raw_State matches the raw state carried by Value.

   function Authoritative_For_Write (Value : State) return Boolean;
   --  Return whether Value originated from a built-in state or model_runner's typed mapping API.
   --  Persisted reconstruction alone is deliberately insufficient at write boundaries.
   --  @param Value State binding to inspect.
   --  @return True when Value may be written as newly resolved harness state.

private
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type State_Origin is (Unknown_Origin, Built_In_Origin, Resolved_Origin, Persisted_Origin);

   type State is record
      Known_Flag : Boolean := False;
      Core       : Model_Runner.Framework.Tasks.Core_State := Model_Runner.Framework.Tasks.Candidate;
      Raw_State  : UString;
      Origin     : State_Origin := Unknown_Origin;
   end record;

   function Restore (Raw_State, Core_State : String) return State;
   --  Reconstruct a binding read from Improve-owned persistence.
   --  @param Raw_State Persisted raw model_runner state.
   --  @param Core_State Persisted canonical core-state spelling.
   --  @return Restored state binding, or an unknown binding when Core_State is invalid.
end Improve.Harness_States;
