with Improve.Workflow_Publication;

package body Improve.Workflow is
   function Publish
     (Project_Directory : String;
      Publication_Namespace : String;
      Plan              : Improve.Model.Plan_Revision;
      Requested_Kind    : String;
      Existing          : Improve.Storage.Publication_Vectors.Vector :=
        Improve.Storage.Publication_Vectors.Empty_Vector;
      Selected_Task_Ids : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector;
      Existing_Only     : Boolean := False;
      Dry_Run           : Boolean := False) return Publication_Result is
   begin
      return Improve.Workflow_Publication.Execute
        (Project_Directory, Publication_Namespace, Plan, Requested_Kind, Existing,
         Selected_Task_Ids, Existing_Only, Dry_Run);
   end Publish;

end Improve.Workflow;
