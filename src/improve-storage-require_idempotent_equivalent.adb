--  Validate semantic equality after a plan-fingerprint idempotency hit.
separate (Improve.Storage)
procedure Require_Idempotent_Equivalent
  (Existing, Candidate : Improve.Model.Plan_Revision) is
   use type Improve.Model.Finding_Reference;
   Existing_Findings : String_Id_Maps.Map;
   Existing_Tasks    : String_Id_Maps.Map;
   Candidate_Tasks   : String_Id_Maps.Map;

   function Normalized_Contract
     (Plan  : Improve.Model.Plan_Revision;
      Index : Positive;
      Tasks : String_Id_Maps.Map) return String is
      Spec : Improve.Model.Task_Specification := Plan.Tasks (Index);
   begin
      for Dependency in 1 .. Natural (Spec.Dependencies.Length) loop
         declare Id : constant String := To_String (Spec.Dependencies (Dependency)); begin
            if not Tasks.Contains (Id) then
               raise Data_Error with "plan dependency is absent from its task graph";
            end if;
            Spec.Dependencies.Replace_Element
              (Dependency, To_Unbounded_String ("@task:" & Number (Tasks.Element (Id))));
         end;
      end loop;
      return Improve.Model.Task_Contract_Fingerprint (Spec);
   end Normalized_Contract;
begin
   if Existing.Project.Id /= Candidate.Project.Id or else
     Existing.Project.Name /= Candidate.Project.Name or else
     Existing.Project.Path /= Candidate.Project.Path or else
     Existing.Project.Database_Id /= Candidate.Project.Database_Id
   then
      raise Data_Error with "plan revision fingerprint conflicts with durable project identity";
   elsif Existing.Baseline.Project_Id /= Candidate.Baseline.Project_Id or else
     Existing.Baseline.Run_Id /= Candidate.Baseline.Run_Id or else
     Existing.Baseline.Source_Id /= Candidate.Baseline.Source_Id or else
     Existing.Baseline.Policy_Id /= Candidate.Baseline.Policy_Id or else
     Existing.Baseline.Toolchain_Id /= Candidate.Baseline.Toolchain_Id or else
     Existing.Baseline.Evidence_Id /= Candidate.Baseline.Evidence_Id
   then
      raise Data_Error with "plan revision fingerprint conflicts with durable assessment provenance";
   elsif Existing.Working_Source_Id /= Candidate.Working_Source_Id then
      raise Data_Error with "plan revision fingerprint conflicts with durable working source";
   elsif Existing.Planner_Id /= Candidate.Planner_Id then
      raise Data_Error with "plan revision fingerprint conflicts with durable planner identity";
   elsif Existing.Review_Status /= Candidate.Review_Status then
      raise Data_Error with "plan revision fingerprint conflicts with durable review state";
   elsif Existing.Findings.Length /= Candidate.Findings.Length then
      raise Data_Error with "plan revision fingerprint conflicts with durable finding count";
   elsif Existing.Tasks.Length /= Candidate.Tasks.Length then
      raise Data_Error with "plan revision fingerprint conflicts with durable task count";
   end if;
   for Index in 1 .. Natural (Existing.Findings.Length) loop
      Existing_Findings.Insert
        (Improve.Model.Finding_Key (Existing.Findings (Index)), Index);
   end loop;
   for Index in 1 .. Natural (Existing.Tasks.Length) loop
      Existing_Tasks.Insert (To_String (Existing.Tasks (Index).Id), Index);
      Candidate_Tasks.Insert (To_String (Candidate.Tasks (Index).Id), Index);
   end loop;
   for Candidate_Finding of Candidate.Findings loop
      declare
         Key : constant String := Improve.Model.Finding_Key (Candidate_Finding);
      begin
         if not Existing_Findings.Contains (Key) or else
           Existing.Findings (Existing_Findings.Element (Key)) /= Candidate_Finding
         then
            raise Data_Error with "plan revision fingerprint conflicts with durable finding content";
         end if;
      end;
   end loop;
   for Index in 1 .. Natural (Existing.Tasks.Length) loop
      if Normalized_Contract (Existing, Index, Existing_Tasks) /=
        Normalized_Contract (Candidate, Index, Candidate_Tasks)
      then
         raise Data_Error with "plan revision fingerprint conflicts with durable task content";
      end if;
   end loop;
end Require_Idempotent_Equivalent;
