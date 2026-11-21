package Improve.Harness_States.Persistence is
   --  Persistence-only reconstruction of an Improve-owned raw/core binding.

   function Restore (Raw_State, Core_State : String) return State;
   --  Restore a binding already validated as Improve-owned persisted data.
   --  @param Raw_State Persisted raw model_runner state.
   --  @param Core_State Persisted canonical core-state spelling.
   --  @return Restored state binding, or an unknown binding when Core_State is invalid.
end Improve.Harness_States.Persistence;
