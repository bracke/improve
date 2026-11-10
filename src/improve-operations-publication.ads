with Improve.Model;
with Improve.Workflow;

--  Publication authorization, journaling, and native task creation.
package Improve.Operations.Publication is
   type Result is record
      Plan      : Improve.Model.Plan_Revision;
      Published : Improve.Workflow.Publication_Result;
   end record;

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Plan_Id          : String;
      Selected_Task_Id : String;
      Task_Kind        : String;
      Dry_Run          : Boolean) return Result;
end Improve.Operations.Publication;
