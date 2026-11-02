with Improve.Config;
with Improve.Model;
with Improve.Source;

--  Deterministic transformation of normalized evidence into bounded work.
package Improve.Planner is
   Planner_Version : constant String := "deterministic-v1";

   function Generate
     (Selected : Improve.Source.Selection;
      Findings : Improve.Model.Finding_Vectors.Vector;
      Settings : Improve.Config.Settings) return Improve.Model.Plan_Revision;
   --  Group related evidence, split oversized groups, and generate explicit task
   --  specifications. Equal inputs and planner configuration produce the same
   --  plan fingerprint and task definitions.
   --  @exception Data_Error Evidence cannot form a safe plan or limits are exceeded.
end Improve.Planner;
