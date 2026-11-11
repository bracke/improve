with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Source;
with Improve.Storage;

package body Improve.Operations.Verification is
   use Ada.Strings.Unbounded;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Storage.Verification_Scope;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Run
     (State_Path       : String;
      Quality_Path     : String;
      Project_Selector : String;
      Task_Id          : String;
      Revision         : Natural;
      Run_Id           : Natural;
      Settings         : Improve.Config.Settings) return Result
   is
      State : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
      Previously_Verified : Improve.Model.UString_Vectors.Vector;
      Limits : constant Improve.Storage.Read_Limits := Improve.Operations.Storage_Read_Limits (Settings);
   begin
      Improve.Storage.Open (State, State_Path, Writable => False);
      if Task_Id /= "" then
         Plan := Improve.Storage.Load_Task (State, Task_Id, Revision, Limits);
      else
         declare
            Quality : Improve.Source.Repository;
            Project : Improve.Model.Project_Reference;
         begin
            Improve.Source.Open (Quality, Quality_Path);
            Project := Improve.Source.Resolve_Project (Quality, Project_Selector);
            Improve.Source.Close (Quality);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project, Limits.Maximum_History);
            begin
               if Values.Is_Empty then
                  raise Argument_Error with "project has no stored remediation plan";
               end if;
               Plan :=
                 (if Revision > 0 then
                     Improve.Storage.Load
                       (State, To_String (Values.Last_Element.Plan_Id), Positive (Revision), Limits)
                  else Improve.Storage.Load (State, To_String (Values.Last_Element.Plan_Id), Limits));
            end;
         end;
      end if;
      Improve.Storage.Close (State);
      declare
         Quality : Improve.Source.Repository;
      begin
         Improve.Source.Open (Quality, Quality_Path);
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Current : constant Improve.Source.Selection :=
              Improve.Source.Select_Assessment (Quality, Project, Run_Id);
         begin
            Improve.Operations.Require_Project_Identity (Plan.Project, Project);
            Improve.Source.Close (Quality);
            Improve.Storage.Open (State, State_Path, Writable => False);
            for Record_Value of Improve.Storage.Verifications
              (State, To_String (Plan.Plan_Id), Maximum => Limits.Maximum_History, Limits => Limits)
            loop
               for Spec of Plan.Tasks loop
                  if Record_Value.Scope = Improve.Storage.Task_Evaluation and then
                    Record_Value.Task_Id = Spec.Id and then
                    To_String (Record_Value.Contract_Fingerprint) =
                      Improve.Verification.Contract_Fingerprint (Spec) and then
                    Record_Value.Assessment_Id < Current.Baseline.Run_Id and then
                    Record_Value.Outcome = Improve.Model.Verified and then
                    not Previously_Verified.Contains (Record_Value.Task_Id)
                  then
                     Previously_Verified.Append (Record_Value.Task_Id);
                     exit;
                  end if;
               end loop;
            end loop;
            Improve.Storage.Close (State);
            declare
               Report : constant Improve.Verification.Report :=
                 Improve.Verification.Evaluate (Plan, Current, Settings, Task_Id, Previously_Verified);
               Records : Improve.Storage.Verification_Vectors.Vector;
            begin
               for Task_Result of Report.Tasks loop
                  for Spec of Plan.Tasks loop
                     if Spec.Id = Task_Result.Task_Id then
                        Records.Append
                          (Improve.Storage.Verification_Record'
                             (Scope                => Improve.Storage.Task_Evaluation,
                              Task_Id              => Task_Result.Task_Id,
                              Plan_Revision        => Plan.Revision,
                              Contract_Fingerprint => To_Unbounded_String
                                (Improve.Verification.Contract_Fingerprint (Spec)),
                              Assessment_Id        => Report.Verification_Run,
                              Outcome              => Task_Result.Outcome,
                              Comparable           => Report.Comparable,
                              Explanation          => Task_Result.Explanation));
                        exit;
                     end if;
                  end loop;
               end loop;
               if Task_Id = "" then
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope                => Improve.Storage.Plan_Evaluation,
                        Task_Id              => Null_Unbounded_String,
                        Plan_Revision        => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id        => Report.Verification_Run,
                        Outcome              => Report.Plan_Outcome,
                        Comparable           => Report.Comparable,
                        Explanation          => Report.Explanation));
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope                => Improve.Storage.Project_Evaluation,
                        Task_Id              => Null_Unbounded_String,
                        Plan_Revision        => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id        => Report.Verification_Run,
                        Outcome              => Report.Project_Outcome,
                        Comparable           => Report.Comparable,
                        Explanation          => Report.Explanation));
               end if;
               Improve.Storage.Open (State, State_Path, Writable => True);
               Improve.Storage.Record_Verification (State, To_String (Plan.Plan_Id), Records);
               Improve.Storage.Close (State);
               return (Plan => Plan, Report => Report);
            end;
         end;
      end;
   end Run;
end Improve.Operations.Verification;
