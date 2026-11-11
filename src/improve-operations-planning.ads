with Improve.Config;
with Improve.Model;
with Improve.Storage;

--  Deterministic planning and immutable plan-history use cases.
package Improve.Operations.Planning is
   type Generation_Result is record
      Plan     : Improve.Model.Plan_Revision;
      Existing : Boolean := False;
   end record;
   --  Generated plan and whether persistence reused identical content.

   function Generate
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings;
      Dry_Run          : Boolean) return Generation_Result;
   --  Generate a deterministic plan and persist it unless Dry_Run is true.

   function Load
     (State_Path : String;
      Plan_Id    : String;
      Revision   : Natural := 0) return Improve.Model.Plan_Revision;
   --  Load the latest or an exact immutable plan revision.

   function List
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String) return Improve.Storage.Summary_Vectors.Vector;
   --  List stored plans for one database-qualified project.

   function Approve
     (State_Path : String;
      Plan_Id    : String) return Improve.Model.Plan_Revision;
   --  Approve the latest immutable revision and return it.
end Improve.Operations.Planning;
