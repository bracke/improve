package body Improve.Harness_States.Persistence is
   function Restore (Raw_State, Core_State : String) return State is
     (Improve.Harness_States.Restore (Raw_State, Core_State));
end Improve.Harness_States.Persistence;
