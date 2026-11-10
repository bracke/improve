with Improve.Config;
with Improve.Model;
with Improve.Verification;

--  Assessment-scoped verification selection and persistence.
package Improve.Operations.Verification is
   type Result is record
      Plan   : Improve.Model.Plan_Revision;
      Report : Improve.Verification.Report;
   end record;

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings) return Result;
end Improve.Operations.Verification;
