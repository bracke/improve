with Ada_Quality.Reporting;
with Improve.Model;

--  Shared source and quality-evidence authorization for native publication.
package Improve.Publication_Authorization is
   --  One authorization contract shared by publication and recovery.
   procedure Validate
     (Plan           : Improve.Model.Plan_Revision;
      State_Path     : String;
      Quality_Path      : String;
      Quality_Limits    : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Quality_Database_Bytes : Positive := 1_073_741_824;
      Maximum_Assessment_Bytes : Positive := 16_777_216;
      Retain_On_Failure : Boolean := False);
   --  Require the current working source and latest completed quality evidence
   --  to remain compatible with an immutable publication plan.
   --  @param Plan Exact immutable plan proposed for publication.
   --  @param State_Path Improve database excluded from working-source identity.
   --  @param Quality_Path Read-only Ada Quality database.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Maximum_Quality_Database_Bytes Maximum quality database file bytes accepted.
   --  @param Maximum_Assessment_Bytes Maximum typed assessment evidence bytes accepted.
   --  @param Retain_On_Failure Add recovery-specific retention context to failures.
end Improve.Publication_Authorization;
