with Improve.Verification;

package body Improve.Tasks is
   use Ada.Strings.Unbounded;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Storage.Verification_Scope;

   function Image (Value : Operational_Status) return String is
     (case Value is
         when Proposed => "proposed",
         when Published => "published",
         when In_Progress => "in_progress",
         when Awaiting_Verification => "awaiting_verification",
         when Verified => "verified",
         when Blocked => "blocked",
         when Failed => "failed",
         when Cancelled => "cancelled",
         when Rejected => "rejected",
         when Partially_Resolved => "partially_resolved",
         when Still_Failing => "still_failing",
         when Inconclusive => "inconclusive",
         when Regressed => "regressed",
         when Superseded => "superseded");

   function Status_Of
     (Harness          : String;
      Quality          : Improve.Model.Quality_Outcome;
      Has_Verification : Boolean) return Operational_Status is
   begin
      if Has_Verification and then Quality = Improve.Model.Verified and then
        Harness in "complete" | "verification"
      then
         return Verified;
      elsif Has_Verification and then Quality = Improve.Model.Regressed then return Regressed;
      elsif Has_Verification and then Quality = Improve.Model.Superseded then return Superseded;
      elsif Harness = "" then return Proposed;
      elsif Harness = "running" then return In_Progress;
      elsif Harness = "blocked" then return Blocked;
      elsif Harness = "failed" then return Failed;
      elsif Harness = "cancelled" then return Cancelled;
      elsif Harness = "rejected" then return Rejected;
      elsif Harness in "complete" | "verification" and then Has_Verification then
         case Quality is
            when Improve.Model.Partially_Resolved => return Partially_Resolved;
            when Improve.Model.Still_Failing => return Still_Failing;
            when Improve.Model.Inconclusive => return Inconclusive;
            when others => return Awaiting_Verification;
         end case;
      elsif Harness in "complete" | "verification" then
         return Awaiting_Verification;
      else
         return Published;
      end if;
   end Status_Of;

   function Build
     (Plan          : Improve.Model.Plan_Revision;
      Publications  : Improve.Storage.Publication_Vectors.Vector;
      Verifications : Improve.Storage.Verification_Vectors.Vector;
      Current_Assessment : Natural := 0) return View_Vectors.Vector is
      Result : View_Vectors.Vector;
   begin
      for Spec of Plan.Tasks loop
         declare
            View       : Task_View;
            Latest_Run : Natural := 0;
         begin
            View.Project_Id := Plan.Project.Id;
            View.Project := Plan.Project.Name;
            View.Plan_Id := Plan.Plan_Id;
            View.Improve_Id := Spec.Id;
            View.Title := Spec.Title;
            for Published of Publications loop
               if Published.Improve_Task_Id = Spec.Id and then
                 To_String (Published.Contract) =
                   Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Spec.Id)
               then
                  View.Harness_Id := Published.Harness_Task_Id;
                  View.Harness_State := Published.State;
                  exit;
               end if;
            end loop;
            for Verification of Verifications loop
               if Verification.Scope = Improve.Storage.Task_Evaluation and then
                 Verification.Task_Id = Spec.Id and then
                 Verification.Plan_Revision = Plan.Revision and then
                 To_String (Verification.Contract_Fingerprint) =
                   Improve.Verification.Contract_Fingerprint (Spec) and then
                 Verification.Assessment_Id >= Latest_Run
               then
                  Latest_Run := Verification.Assessment_Id;
                  View.Quality := Verification.Outcome;
                  View.Has_Verification := True;
                  View.Verification_Run := Verification.Assessment_Id;
               end if;
            end loop;
            View.Verification_Current :=
              View.Has_Verification and then Current_Assessment > 0 and then Latest_Run = Current_Assessment;
            View.Status := Status_Of
              (To_String (View.Harness_State), View.Quality, View.Verification_Current);
            Result.Append (View);
         end;
      end loop;
      return Result;
   end Build;

   function "<" (Left, Right : Task_View) return Boolean is
     (Left.Project_Id < Right.Project_Id or else
        (Left.Project_Id = Right.Project_Id and then
           (Left.Plan_Id < Right.Plan_Id or else
              (Left.Plan_Id = Right.Plan_Id and then Left.Improve_Id < Right.Improve_Id))));

   package Sorting is new View_Vectors.Generic_Sorting ("<" => "<");

   procedure Sort (Values : in out View_Vectors.Vector) is
   begin
      Sorting.Sort (Values);
   end Sort;

   function Valid_Filter (Value : String) return Boolean is
   begin
      if Value in "" | "all" | "unresolved" then return True; end if;
      for Status in Operational_Status loop
         if Image (Status) = Value then return True; end if;
      end loop;
      return False;
   end Valid_Filter;

   function Matches (Value : Task_View; Filter : String) return Boolean is
   begin
      if Filter in "" | "all" then return True;
      elsif Filter = "unresolved" then return Value.Status not in Verified | Superseded;
      else return Image (Value.Status) = Filter;
      end if;
   end Matches;

   function Findings
     (Plan  : Improve.Model.Plan_Revision;
      Views : View_Vectors.Vector) return Finding_Summary is
      Result : Finding_Summary;
   begin
      for Finding of Plan.Findings loop
         declare
            Linked       : Natural := 0;
            All_Verified : Boolean := True;
            Any_Unknown  : Boolean := False;
            Any_Regressed : Boolean := False;
            All_Superseded : Boolean := True;
            Any_Current : Boolean := False;
            All_Previously_Verified : Boolean := True;
         begin
            for Index in 1 .. Natural (Plan.Tasks.Length) loop
               if Plan.Tasks (Index).Finding_Keys.Contains (Finding.Fingerprint) then
                  Linked := Linked + 1;
                  declare View : constant Task_View := Views (Index); begin
                     Any_Current := Any_Current or else View.Verification_Current;
                     All_Verified := All_Verified and then
                       View.Verification_Current and then View.Quality = Improve.Model.Verified;
                     All_Superseded := All_Superseded and then
                       View.Verification_Current and then View.Quality = Improve.Model.Superseded;
                     Any_Unknown := Any_Unknown or else
                       (View.Verification_Current and then View.Quality = Improve.Model.Inconclusive);
                     Any_Regressed := Any_Regressed or else
                       (View.Verification_Current and then View.Quality = Improve.Model.Regressed);
                     All_Previously_Verified := All_Previously_Verified and then
                       View.Has_Verification and then not View.Verification_Current and then
                       View.Quality = Improve.Model.Verified;
                  end;
               end if;
            end loop;
            if Linked = 0 then Result.Outstanding := Result.Outstanding + 1;
            elsif Any_Regressed then Result.Regressed := Result.Regressed + 1;
            elsif All_Verified then Result.Resolved := Result.Resolved + 1;
            elsif All_Superseded then Result.Superseded := Result.Superseded + 1;
            elsif Any_Unknown then Result.Not_Measurable := Result.Not_Measurable + 1;
            elsif not Any_Current and then All_Previously_Verified then
               Result.Previously_Resolved := Result.Previously_Resolved + 1;
            elsif not Any_Current then Result.Unverified := Result.Unverified + 1;
            else Result.Outstanding := Result.Outstanding + 1;
            end if;
         end;
      end loop;
      return Result;
   end Findings;
end Improve.Tasks;
