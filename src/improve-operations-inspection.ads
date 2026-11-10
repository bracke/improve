with Improve.Model;
with Improve.Tasks;

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
      Maximum_Items    : Positive) return Improve.Tasks.View_Vectors.Vector;
   --  Return filtered task views for an optional database-qualified project or task.

   function Status
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      All_Projects     : Boolean;
      Maximum_Items    : Positive) return Improve.Tasks.Status_Vectors.Vector;
   --  Return assessment-aware remediation status for one or every registered project.

   procedure Require_Project_Identity
     (Stored, Current : Improve.Model.Project_Reference);
   --  Reject equal numeric project identifiers from different quality databases or roots.
end Improve.Operations.Inspection;
