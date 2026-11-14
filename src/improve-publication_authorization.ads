with Ada_Quality.Reporting;
with Improve.Config;
with Improve.Model;

--  Shared source and quality-evidence authorization for native publication.
package Improve.Publication_Authorization is
   --  One authorization contract shared by publication and recovery.
   procedure Validate
     (Plan           : Improve.Model.Plan_Revision;
      State_Path     : String;
      Quality_Path      : String;
      Quality_Limits    : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits   : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits;
      Retain_On_Failure : Boolean := False);
   --  Require the current working source and latest completed quality evidence
   --  to remain compatible with an immutable publication plan.
   --  @param Plan Exact immutable plan proposed for publication.
   --  @param State_Path Improve database excluded from working-source identity.
   --  @param Quality_Path Read-only Ada Quality database.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @param Retain_On_Failure Add recovery-specific retention context to failures.
end Improve.Publication_Authorization;
