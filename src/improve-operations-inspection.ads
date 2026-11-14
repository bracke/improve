with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Model;
with Improve.Source;
with Improve.Storage;
with Improve.Tasks;
with Ada_Quality.Reporting;

--  Read-only task and project status use cases.
package Improve.Operations.Inspection is
   --  Assemble assessment-aware inspection models independently of presentation.

   type Project_Result is record
      Values   : Ada_Quality.Reporting.Project_Vectors.Vector;
      Snapshot : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Registered projects and the reporting snapshot from which they were read.
   --  @field Values Registered projects in stable reporting order.
   --  @field Snapshot Read-only reporting snapshot identity.

   type Finding_Result is record
      Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector;
   end record;
   --  One completed assessment selection and its normalized remediation findings.
   --  @field Selected Completed assessment and project provenance.
   --  @field Values Normalized remediation findings in deterministic order.

   function Projects
     (Quality_Path : String;
      Settings     : Improve.Config.Settings) return Project_Result;
   --  Read the bounded project registry through the typed reporting interface.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Settings Validated quality and output limits.
   --  @return Registered projects and reporting snapshot identity.

   function Findings
     (Quality_Path     : String;
      Project_Selector : String;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings) return Finding_Result;
   --  Select a completed assessment and normalize its bounded remediation evidence.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name.
   --  @param Run_Id Explicit completed assessment, or zero for the latest completed run.
   --  @param Settings Validated evidence, planning, and output limits.
   --  @return Assessment selection and normalized findings.

   function Tasks
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Filter           : String;
      Maximum_Items    : Positive;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits)
      return Improve.Tasks.View_Vectors.Vector;
   --  Return filtered task views for an optional database-qualified project or task.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique project name, or empty for every stored project.
   --  @param Task_Id One logical task identity, or empty for every matching task.
   --  @param Revision Exact historical plan revision, or zero for the latest task definition.
   --  @param Filter Valid operational status filter.
   --  @param Maximum_Items Hard result-size limit.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @return Stable, filtered, assessment-aware task views.

   function Status
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      All_Projects     : Boolean;
      Maximum_Items    : Positive;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits  : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits)
      return Improve.Tasks.Status_Vectors.Vector;
   --  Return assessment-aware remediation status for one or every registered project.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique name; ignored when All_Projects is true.
   --  @param All_Projects Whether to inspect every registered project.
   --  @param Maximum_Items Hard project and task result-size limit.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @return Stable project status models with freshness-qualified evidence.

end Improve.Operations.Inspection;
