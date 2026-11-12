with Improve.Storage;
with Improve.Tasks;
with Ada_Quality.Reporting;

--  Read-only task and project status use cases.
package Improve.Operations.Inspection is
   --  Assemble assessment-aware inspection models independently of presentation.

   function Tasks
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Filter           : String;
      Maximum_Items    : Positive;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>))
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
   --  @return Stable, filtered, assessment-aware task views.

   function Status
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      All_Projects     : Boolean;
      Maximum_Items    : Positive;
      Limits           : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits   : Ada_Quality.Reporting.Load_Limits := (others => <>))
      return Improve.Tasks.Status_Vectors.Vector;
   --  Return assessment-aware remediation status for one or every registered project.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Project_Selector Project identity or unique name; ignored when All_Projects is true.
   --  @param All_Projects Whether to inspect every registered project.
   --  @param Maximum_Items Hard project and task result-size limit.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot load limits.
   --  @return Stable project status models with freshness-qualified evidence.

end Improve.Operations.Inspection;
