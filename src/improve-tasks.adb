with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package body Improve.Tasks is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Storage.Verification_Scope;

   package Index_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Positive,
      Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

   package Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => UString,
      Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

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
      Current_Assessment : Natural := 0;
      Maximum_Items : Positive := Improve.Storage.Default_Query_Maximum) return View_Vectors.Vector is
      Result : View_Vectors.Vector;
      Contracts : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
        Improve.Model.Effective_Task_Contracts (Plan);
      Effective : Value_Maps.Map;
      Specifications : Index_Maps.Map;
      Published_By_Contract : Index_Maps.Map;
      Latest_Verification : Index_Maps.Map;
   begin
      if Plan.Tasks.Length > Ada.Containers.Count_Type (Maximum_Items) then
         raise Improve.Data_Error with "task view exceeds configured item limit";
      end if;
      for Binding of Contracts loop
         Effective.Insert (To_String (Binding.Task_Id), Binding.Fingerprint);
      end loop;
      for Index in 1 .. Natural (Plan.Tasks.Length) loop
         declare Identity : constant String := To_String (Plan.Tasks (Index).Id); begin
            if Specifications.Contains (Identity) then
               raise Improve.Data_Error with "duplicate task specification " & Identity;
            end if;
            Specifications.Insert (Identity, Index);
         end;
      end loop;
      for Index in 1 .. Natural (Publications.Length) loop
         declare
            Key : constant String :=
              To_String (Publications (Index).Improve_Task_Id) & Character'Val (0) &
              To_String (Publications (Index).Contract);
         begin
            if not Published_By_Contract.Contains (Key) then
               Published_By_Contract.Insert (Key, Index);
            end if;
         end;
      end loop;
      for Index in 1 .. Natural (Verifications.Length) loop
         declare
            Verification : Improve.Storage.Verification_Record renames Verifications (Index);
            Identity     : constant String := To_String (Verification.Task_Id);
         begin
            if Verification.Scope = Improve.Storage.Task_Evaluation and then
              Specifications.Contains (Identity) and then
              Verification.Plan_Revision = Plan.Revision and then
              Verification.Contract_Fingerprint = Effective.Element (Identity)
            then
               if not Latest_Verification.Contains (Identity) or else
                 Verifications (Latest_Verification.Element (Identity)).Assessment_Id <=
                   Verification.Assessment_Id
               then
                  Latest_Verification.Include (Identity, Index);
               end if;
            end if;
         end;
      end loop;
      for Spec of Plan.Tasks loop
         declare
            View       : Task_View;
            Identity   : constant String := To_String (Spec.Id);
            Contract   : constant String := To_String (Effective.Element (Identity));
            Mapping_Key : constant String := Identity & Character'Val (0) & Contract;
         begin
            View.Project_Id := Plan.Project.Id;
            View.Project := Plan.Project.Name;
            View.Plan_Id := Plan.Plan_Id;
            View.Improve_Id := Spec.Id;
            View.Title := Spec.Title;
            if Published_By_Contract.Contains (Mapping_Key) then
               declare
                  Published : Improve.Storage.Publication_Record renames
                    Publications (Published_By_Contract.Element (Mapping_Key));
               begin
                  View.Harness_Id := Published.Harness_Task_Id;
                  View.Harness_State := Published.State;
               end;
            end if;
            if Latest_Verification.Contains (Identity) then
               declare
                  Verification : Improve.Storage.Verification_Record renames
                    Verifications (Latest_Verification.Element (Identity));
               begin
                  View.Quality := Verification.Outcome;
                  View.Has_Verification := True;
                  View.Verification_Run := Verification.Assessment_Id;
               end;
            end if;
            View.Verification_Current :=
              View.Has_Verification and then Current_Assessment > 0 and then
              View.Verification_Run = Current_Assessment;
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
      type Finding_State is record
         Linked                  : Natural := 0;
         All_Verified            : Boolean := True;
         Any_Unknown             : Boolean := False;
         Any_Regressed           : Boolean := False;
         All_Superseded          : Boolean := True;
         Any_Current             : Boolean := False;
         All_Previously_Verified : Boolean := True;
      end record;

      package Finding_Maps is new Ada.Containers.Indefinite_Hashed_Maps
        (Key_Type => String, Element_Type => Finding_State,
         Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

      View_Indexes : Index_Maps.Map;
      States       : Finding_Maps.Map;
   begin
      for Index in 1 .. Natural (Views.Length) loop
         declare Identity : constant String := To_String (Views (Index).Improve_Id); begin
            if View_Indexes.Contains (Identity) then
               raise Improve.Data_Error with "duplicate task view " & Identity;
            end if;
            View_Indexes.Insert (Identity, Index);
         end;
      end loop;
      for Finding of Plan.Findings loop
         declare Key : constant String := To_String (Finding.Fingerprint); begin
            if States.Contains (Key) then
               raise Improve.Data_Error with "duplicate plan finding " & Key;
            end if;
            States.Insert (Key, Finding_State'(others => <>));
         end;
      end loop;
      for Spec of Plan.Tasks loop
         declare Identity : constant String := To_String (Spec.Id); begin
            if not View_Indexes.Contains (Identity) then
               raise Improve.Data_Error with "missing task view " & Identity;
            end if;
            declare View : Task_View renames Views (View_Indexes.Element (Identity)); begin
               for Finding_Key of Spec.Finding_Keys loop
                  declare Key : constant String := To_String (Finding_Key); begin
                     if States.Contains (Key) then
                        declare State : Finding_State := States.Element (Key); begin
                           State.Linked := State.Linked + 1;
                           State.Any_Current := State.Any_Current or else View.Verification_Current;
                           State.All_Verified := State.All_Verified and then
                             View.Verification_Current and then View.Quality = Improve.Model.Verified;
                           State.All_Superseded := State.All_Superseded and then
                             View.Verification_Current and then View.Quality = Improve.Model.Superseded;
                           State.Any_Unknown := State.Any_Unknown or else
                             (View.Verification_Current and then View.Quality = Improve.Model.Inconclusive);
                           State.Any_Regressed := State.Any_Regressed or else
                             (View.Verification_Current and then View.Quality = Improve.Model.Regressed);
                           State.All_Previously_Verified := State.All_Previously_Verified and then
                             View.Has_Verification and then not View.Verification_Current and then
                             View.Quality = Improve.Model.Verified;
                           States.Replace (Key, State);
                        end;
                     end if;
                  end;
               end loop;
            end;
         end;
      end loop;
      for Finding of Plan.Findings loop
         declare
            State : constant Finding_State := States.Element (To_String (Finding.Fingerprint));
         begin
            if State.Linked = 0 then Result.Outstanding := Result.Outstanding + 1;
            elsif State.Any_Regressed then Result.Regressed := Result.Regressed + 1;
            elsif State.All_Verified then Result.Resolved := Result.Resolved + 1;
            elsif State.All_Superseded then Result.Superseded := Result.Superseded + 1;
            elsif State.Any_Unknown then Result.Not_Measurable := Result.Not_Measurable + 1;
            elsif not State.Any_Current and then State.All_Previously_Verified then
               Result.Previously_Resolved := Result.Previously_Resolved + 1;
            elsif not State.Any_Current then Result.Unverified := Result.Unverified + 1;
            else Result.Outstanding := Result.Outstanding + 1;
            end if;
         end;
      end loop;
      return Result;
   end Findings;
end Improve.Tasks;
