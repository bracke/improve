separate (Improve.JSON)
function Audit
  (Value        : Improve.Results.Audit_Bundle;
   Next_Cursor  : String := "";
   Signing_Seed : String := "") return String is
   Doc           : Document;
   Context       : constant Envelope := Start_Envelope (Doc, "audit");
   Publications  : constant Node := Doc.New_Array;
   Verifications : constant Node := Doc.New_Array;
   Tasks         : constant Node := Doc.New_Array;
   Findings      : constant Node := Doc.New_Array;
   Plan          : Improve.Model.Plan_Revision renames Value.Plan;
   Public_Key    : Unbounded_String;
   Signature     : Unbounded_String;
begin
   Doc.Insert (Context.Data, "plan_id", Doc.New_String (To_String (Plan.Plan_Id)));
   Doc.Insert (Context.Data, "revision", Doc.New_Integer (Long_Long_Integer (Plan.Revision)));
   Doc.Insert (Context.Data, "fingerprint", Doc.New_String (To_String (Plan.Fingerprint)));
   Doc.Insert (Context.Data, "approved", Doc.New_Boolean (Value.Approved));
   Doc.Insert (Context.Data, "project_id", Doc.New_Integer (Long_Long_Integer (Plan.Project.Id)));
   Doc.Insert (Context.Data, "project", Doc.New_String (To_String (Plan.Project.Name)));
   Doc.Insert (Context.Data, "database_id", Doc.New_String (To_String (Plan.Project.Database_Id)));
   Doc.Insert (Context.Data, "baseline_run", Doc.New_Integer (Long_Long_Integer (Plan.Baseline.Run_Id)));
   Doc.Insert (Context.Data, "source_id", Doc.New_String (To_String (Plan.Baseline.Source_Id)));
   Doc.Insert (Context.Data, "policy_id", Doc.New_String (To_String (Plan.Baseline.Policy_Id)));
   Doc.Insert (Context.Data, "toolchain_id", Doc.New_String (To_String (Plan.Baseline.Toolchain_Id)));
   Doc.Insert (Context.Data, "evidence_id", Doc.New_String (To_String (Plan.Baseline.Evidence_Id)));
   Doc.Insert (Context.Data, "planner_id", Doc.New_String (To_String (Plan.Planner_Id)));
   Doc.Insert
     (Context.Data, "agent_provider", Doc.New_String (To_String (Plan.Agent_Provider_Id)));
   Doc.Insert
     (Context.Data, "agent_model_sha256", Doc.New_String (To_String (Plan.Agent_Model_SHA256)));
   for Finding of Plan.Findings loop
      Doc.Append (Findings, Doc.New_String (Improve.Model.Finding_Key (Finding)));
   end loop;
   Doc.Insert (Context.Data, "finding_keys", Findings);
   for Spec of Plan.Tasks loop
      declare
         Item : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Item, "id", Doc.New_String (To_String (Spec.Id)));
         Doc.Insert (Item, "title", Doc.New_String (To_String (Spec.Title)));
         Doc.Insert
           (Item, "contract_fingerprint",
            Doc.New_String (Improve.Model.Task_Contract_Fingerprint (Spec)));
         Doc.Append (Tasks, Item);
      end;
   end loop;
   Doc.Insert (Context.Data, "tasks", Tasks);
   for History_Item of Value.History.Publications loop
      declare
         Item : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Item, "improve_task_id", Doc.New_String (To_String (History_Item.Improve_Task_Id)));
         Doc.Insert (Item, "harness_task_id", Doc.New_String (To_String (History_Item.Harness_Task_Id)));
         Doc.Insert (Item, "origin", Doc.New_String (To_String (History_Item.Origin)));
         Doc.Insert (Item, "contract", Doc.New_String (To_String (History_Item.Contract)));
         Doc.Insert (Item, "state", Doc.New_String (To_String (History_Item.State)));
         Doc.Insert (Item, "core_state", Doc.New_String (Improve.Harness_States.Image (History_Item.Core_State)));
         Doc.Insert
           (Item, "plan_revision", Doc.New_Integer (Long_Long_Integer (History_Item.Plan_Revision)));
         Doc.Append (Publications, Item);
      end;
   end loop;
   Doc.Insert (Context.Data, "publications", Publications);
   for History_Item of Value.History.Verifications loop
      declare
         Item : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Item, "scope", Doc.New_String (Improve.Model.Image (History_Item.Scope)));
         Doc.Insert (Item, "task_id", Doc.New_String (To_String (History_Item.Task_Id)));
         Doc.Insert
           (Item, "plan_revision", Doc.New_Integer (Long_Long_Integer (History_Item.Plan_Revision)));
         Doc.Insert
           (Item, "contract_fingerprint", Doc.New_String (To_String (History_Item.Contract_Fingerprint)));
         Doc.Insert
           (Item, "assessment_id", Doc.New_Integer (Long_Long_Integer (History_Item.Assessment_Id)));
         Doc.Insert (Item, "outcome", Doc.New_String (Improve.Model.Image (History_Item.Outcome)));
         Doc.Insert (Item, "comparable", Doc.New_Boolean (History_Item.Comparable));
         Doc.Insert (Item, "explanation", Doc.New_String (To_String (History_Item.Explanation)));
         Doc.Append (Verifications, Item);
      end;
   end loop;
   Doc.Insert (Context.Data, "verifications", Verifications);
   if Next_Cursor /= "" then Doc.Insert (Context.Data, "next_cursor", Doc.New_String (Next_Cursor)); end if;
   declare
      Canonical : Unbounded_String;
   begin
      declare
         Serialized : constant String := Improve.Audit_Artifacts.Canonical_Data (Doc, Context.Data);
      begin
         Canonical := To_Unbounded_String (Serialized);
      end;
      if Length (Canonical) > Improve.Audit_Artifacts.Maximum_Artifact_Bytes then
         raise Improve.Data_Error with "audit artifact exceeds the maximum supported size";
      end if;
      declare
         Canonical_Text : constant String := To_String (Canonical);
         Escaped        : constant String := Jsonlib.Serializers.Escape (Canonical_Text);
         Digest         : constant String := Improve.Audit_Artifacts.Digest (Canonical_Text);
         Projected      : Long_Long_Integer :=
           Long_Long_Integer (Audit_Envelope_Overhead)
           + Long_Long_Integer (Canonical_Text'Length)
           + Long_Long_Integer (Integrity_Skeleton_Length (Signing_Seed /= ""))
           + Long_Long_Integer (Escaped'Length + Digest'Length + 1);
      begin
         if Signing_Seed /= "" then
            Improve.Audit_Artifacts.Sign (Digest, Signing_Seed, Public_Key, Signature);
            Projected := Projected + Long_Long_Integer (Length (Public_Key) + Length (Signature));
         end if;
         if Projected > Long_Long_Integer (Improve.Audit_Artifacts.Maximum_Artifact_Bytes) then
            raise Improve.Data_Error with "audit artifact exceeds the maximum supported size";
         end if;
         Doc.Insert (Context.Data, "canonical_payload", Doc.New_String (Canonical_Text));
         Doc.Insert (Context.Data, "bundle_digest", Doc.New_String (Digest));
         if Signing_Seed /= "" then
            Doc.Insert (Context.Data, "public_key", Doc.New_String (To_String (Public_Key)));
            Doc.Insert (Context.Data, "signature", Doc.New_String (To_String (Signature)));
         end if;
      end;
   exception
      when Storage_Error =>
         raise Improve.Data_Error with "audit artifact exceeds available serialization capacity";
   end;
   declare
      Result : constant String := Finish_Envelope (Doc, Context);
   begin
      if Result'Length > Improve.Audit_Artifacts.Maximum_Artifact_Bytes then
         raise Improve.Data_Error with "audit artifact exceeds the maximum supported size";
      end if;
      return Result;
   end;
end Audit;
