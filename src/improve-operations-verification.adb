with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Improve.Source;
with Improve.Storage;

package body Improve.Operations.Verification is
   use Ada.Strings.Unbounded;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Model.Verification_Scope;

   package Contract_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Improve.Model.UString,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

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
      Contracts           : Contract_Maps.Map;
      Verified_Ids        : String_Sets.Set;
      Limits : constant Improve.Storage.Read_Limits := Improve.Operations.Storage_Read_Limits (Settings);
   begin
      Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
      if Task_Id /= "" then
         Plan := Improve.Storage.Load_Task (State, Task_Id, Revision, Limits);
      else
         declare
            Quality : Improve.Source.Repository;
            Project : Improve.Model.Project_Reference;
         begin
            Improve.Source.Open
              (Quality, Quality_Path, Improve.Operations.Quality_Load_Limits (Settings),
               Settings.Maximum_Quality_Database_Bytes);
            Project := Improve.Source.Resolve_Project (Quality, Project_Selector);
            Improve.Source.Close (Quality);
            declare Values : constant Improve.Storage.Summary_Vectors.Vector :=
              Improve.Storage.List (State, Project, Limits.Maximum_History, Limits);
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
         Improve.Source.Open
           (Quality, Quality_Path, Improve.Operations.Quality_Load_Limits (Settings),
            Settings.Maximum_Quality_Database_Bytes);
         declare
            Project : constant Improve.Model.Project_Reference :=
              Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
            Current : constant Improve.Source.Selection :=
              Improve.Source.Select_Assessment
                (Quality, Project, Run_Id, Settings.Maximum_Assessment_Bytes);
         begin
            Improve.Operations.Require_Project_Identity (Plan.Project, Project);
            Improve.Source.Close (Quality);
            for Binding of Improve.Model.Effective_Task_Contracts (Plan) loop
               declare Identity : constant String := To_String (Binding.Task_Id); begin
                  if Contracts.Contains (Identity) then
                     raise Data_Error with "plan contains duplicate task identity " & Identity;
                  end if;
                  Contracts.Insert (Identity, Binding.Fingerprint);
               end;
            end loop;
            Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
            for Record_Value of Improve.Storage.Verifications
              (State, To_String (Plan.Plan_Id), Maximum => Limits.Maximum_History, Limits => Limits)
            loop
               declare Identity : constant String := To_String (Record_Value.Task_Id); begin
                  if Record_Value.Scope = Improve.Model.Task_Evaluation and then
                    Contracts.Contains (Identity) and then
                    Record_Value.Contract_Fingerprint = Contracts.Element (Identity) and then
                    Record_Value.Assessment_Id < Current.Baseline.Run_Id and then
                    Record_Value.Outcome = Improve.Model.Verified
                  then
                     Verified_Ids.Include (Identity);
                  end if;
               end;
            end loop;
            for Spec of Plan.Tasks loop
               if Verified_Ids.Contains (To_String (Spec.Id)) then
                  Previously_Verified.Append (Spec.Id);
               end if;
            end loop;
            Improve.Storage.Close (State);
            declare
               Report : constant Improve.Verification.Report :=
                 Improve.Verification.Evaluate (Plan, Current, Settings, Task_Id, Previously_Verified);
               Records : Improve.Storage.Verification_Vectors.Vector;
            begin
               for Task_Result of Report.Tasks loop
                  declare Identity : constant String := To_String (Task_Result.Task_Id); begin
                     if not Contracts.Contains (Identity) then
                        raise Data_Error with "verification returned an unknown task " & Identity;
                     end if;
                     Records.Append
                       (Improve.Storage.Verification_Record'
                          (Scope                => Improve.Model.Task_Evaluation,
                           Task_Id              => Task_Result.Task_Id,
                           Plan_Revision        => Plan.Revision,
                           Contract_Fingerprint => Contracts.Element (Identity),
                           Assessment_Id        => Report.Verification_Run,
                           Outcome              => Task_Result.Outcome,
                           Comparable           => Report.Comparable,
                           Explanation          => Task_Result.Explanation));
                  end;
               end loop;
               if Task_Id = "" then
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope                => Improve.Model.Plan_Evaluation,
                        Task_Id              => Null_Unbounded_String,
                        Plan_Revision        => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id        => Report.Verification_Run,
                        Outcome              => Report.Plan_Outcome,
                        Comparable           => Report.Comparable,
                        Explanation          => Report.Explanation));
                  Records.Append
                    (Improve.Storage.Verification_Record'
                       (Scope                => Improve.Model.Project_Evaluation,
                        Task_Id              => Null_Unbounded_String,
                        Plan_Revision        => Plan.Revision,
                        Contract_Fingerprint => Plan.Fingerprint,
                        Assessment_Id        => Report.Verification_Run,
                        Outcome              => Report.Project_Outcome,
                        Comparable           => Report.Comparable,
                        Explanation          => Report.Explanation));
               end if;
               Improve.Storage.Open (State, State_Path, Writable => True, Limits => Limits);
               Improve.Storage.Record_Verification
                 (State, To_String (Plan.Plan_Id), Records, Limits);
               Improve.Storage.Close (State);
               return (Plan => Plan, Report => Report);
            end;
         end;
      end;
   end Run;
end Improve.Operations.Verification;
