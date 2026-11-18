with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Improve.Plan_Diffs is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Improve.Model.Candidate_Kind;
   use type Improve.Model.Priority;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Find_Task
     (Tasks : Improve.Model.Task_Vectors.Vector;
      Id    : String) return Natural is
   begin
      for Index in 1 .. Natural (Tasks.Length) loop
         if To_String (Tasks (Index).Id) = Id then return Index; end if;
      end loop;
      return 0;
   end Find_Task;

   function Contains_Finding
     (Findings : Improve.Model.Finding_Vectors.Vector;
      Key      : String) return Boolean is
   begin
      for Item of Findings loop
         if Improve.Model.Finding_Key (Item) = Key then return True; end if;
      end loop;
      return False;
   end Contains_Finding;

   function Equal
     (Left, Right : Improve.Model.UString_Vectors.Vector) return Boolean is
   begin
      if Left.Length /= Right.Length then return False; end if;
      for Index in 1 .. Natural (Left.Length) loop
         if Left (Index) /= Right (Index) then return False; end if;
      end loop;
      return True;
   end Equal;

   function Compare
     (Earlier : Improve.Model.Plan_Revision;
      Later   : Improve.Model.Plan_Revision) return Improve.Results.Plan_Comparison is
      Result : Improve.Results.Plan_Comparison :=
        (Plan_Id       => Later.Plan_Id,
         From_Revision => Earlier.Revision,
         To_Revision   => Later.Revision,
         others        => <>);

      procedure Add (Reason : String) is
      begin
         Result.Reasons.Append (To_Unbounded_String (Reason));
         Result.Changed := True;
      end Add;

      procedure Compare_Task
        (Left, Right : Improve.Model.Task_Specification) is
         Id : constant String := To_String (Left.Id);

         procedure Changed (Field : String) is
         begin
            Add ("task " & Id & " field changed: " & Field);
         end Changed;
      begin
         if Left.Title /= Right.Title then Changed ("title"); end if;
         if Left.Category /= Right.Category then Changed ("category"); end if;
         if Left.Task_Priority /= Right.Task_Priority then Changed ("priority"); end if;
         if Left.Goal /= Right.Goal then Changed ("goal"); end if;
         if Left.Problem /= Right.Problem then Changed ("problem"); end if;
         if Left.Evidence /= Right.Evidence then Changed ("evidence"); end if;
         if not Equal (Left.Relevant_Files, Right.Relevant_Files) then Changed ("relevant_files"); end if;
         if Left.Scope /= Right.Scope then Changed ("scope"); end if;
         if Left.Out_Of_Scope /= Right.Out_Of_Scope then Changed ("out_of_scope"); end if;
         if Left.Requirements /= Right.Requirements then Changed ("requirements"); end if;
         if Left.Acceptance /= Right.Acceptance then Changed ("acceptance"); end if;
         if Left.Verification /= Right.Verification then Changed ("verification"); end if;
         if not Equal (Left.Dependencies, Right.Dependencies) then Changed ("dependencies"); end if;
         if not Equal (Left.Finding_Keys, Right.Finding_Keys) then Changed ("finding_keys"); end if;
         if Left.Confidence /= Right.Confidence then Changed ("confidence"); end if;
         if Left.Requires_Review /= Right.Requires_Review then Changed ("requires_review"); end if;
         if Left.Kind /= Right.Kind then Changed ("kind"); end if;
      end Compare_Task;
   begin
      if Earlier.Plan_Id /= Later.Plan_Id then
         raise Argument_Error with "plan diff requires revisions of the same logical plan";
      elsif Earlier.Revision > Later.Revision then
         raise Argument_Error with "plan diff revisions must be in ascending order";
      end if;
      if Earlier.Baseline.Run_Id /= Later.Baseline.Run_Id then
         Add
           ("assessment run changed from " & Number (Earlier.Baseline.Run_Id) & " to " &
            Number (Later.Baseline.Run_Id));
      end if;
      if Earlier.Baseline.Source_Id /= Later.Baseline.Source_Id then Add ("assessment source changed"); end if;
      if Earlier.Baseline.Policy_Id /= Later.Baseline.Policy_Id then Add ("quality policy changed"); end if;
      if Earlier.Baseline.Toolchain_Id /= Later.Baseline.Toolchain_Id then Add ("toolchain changed"); end if;
      if Earlier.Baseline.Evidence_Id /= Later.Baseline.Evidence_Id then Add ("assessment evidence changed"); end if;
      if Earlier.Planner_Id /= Later.Planner_Id then Add ("planner configuration changed"); end if;
      if Earlier.Review_Status /= Later.Review_Status then Add ("review status changed"); end if;
      for Finding of Earlier.Findings loop
         if not Contains_Finding (Later.Findings, Improve.Model.Finding_Key (Finding)) then
            Add ("finding removed: " & Improve.Model.Finding_Key (Finding));
         end if;
      end loop;
      for Finding of Later.Findings loop
         if not Contains_Finding (Earlier.Findings, Improve.Model.Finding_Key (Finding)) then
            Add ("finding added: " & Improve.Model.Finding_Key (Finding));
         end if;
      end loop;
      for Spec of Earlier.Tasks loop
         declare
            Id    : constant String := To_String (Spec.Id);
            Index : constant Natural := Find_Task (Later.Tasks, Id);
         begin
            if Index = 0 then
               Add ("task removed: " & Id);
            elsif Improve.Model.Task_Contract_Fingerprint (Spec) /=
              Improve.Model.Task_Contract_Fingerprint (Later.Tasks (Index))
            then
               Compare_Task (Spec, Later.Tasks (Index));
            end if;
         end;
      end loop;
      for Spec of Later.Tasks loop
         if Find_Task (Earlier.Tasks, To_String (Spec.Id)) = 0 then
            Add ("task added: " & To_String (Spec.Id));
         end if;
      end loop;
      return Result;
   end Compare;

   function Explain
     (Current  : Improve.Model.Plan_Revision;
      Previous : Improve.Model.Plan_Revision) return Improve.Results.Plan_Comparison is
   begin
      if Current.Revision = 1 and then Previous.Revision = Current.Revision then
         return Result : Improve.Results.Plan_Comparison :=
           (Plan_Id       => Current.Plan_Id,
            From_Revision => 1,
            To_Revision   => 1,
            Changed       => True,
            others        => <>)
         do
            Result.Reasons.Append
              (To_Unbounded_String
                 ("initial revision derived from assessment run " & Number (Current.Baseline.Run_Id)));
            Result.Reasons.Append
              (To_Unbounded_String
                 (Number (Natural (Current.Findings.Length)) & " findings produced " &
                  Number (Natural (Current.Tasks.Length)) & " tasks"));
         end return;
      end if;
      return Compare (Previous, Current);
   end Explain;
end Improve.Plan_Diffs;
