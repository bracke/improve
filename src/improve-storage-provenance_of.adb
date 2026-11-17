separate (Improve.Storage)
function Provenance_Of
  (Item     : in out Store;
   Tx       : in out Database.Transactions.Transaction;
   Revision : Entity;
   Payload  : String;
   Limits   : Persistence_Limits;
   Consumed_Bytes : in out Natural) return Stored_Provenance is
   Result : Stored_Provenance;

   procedure Consume (Text, Context : String) is
   begin
      Require_Payload_Limit (Text, Limits, Context);
      if Text'Length > Limits.Maximum_Total_Bytes - Consumed_Bytes then
         raise Data_Error with "plan reconstruction exceeds configured aggregate byte limit";
      end if;
      Consumed_Bytes := Consumed_Bytes + Text'Length;
   end Consume;

   function Required (Table, Id : Positive; Context : String) return Entity is
      Value  : Entity;
      Status : constant Database.Status.Result :=
        Entity_Tables.Find
          (Tx, Item.DB, Item.Schemas (Table), Physical_Key (Table, Id), Value);
   begin
      if Status.Code = Database.Status.Not_Found then
         raise Data_Error with Context & " relationship is missing";
      end if;
      Check (Status, "read " & Context);
      return Value;
   end Required;
begin
   if Item.Schema_Version < 5 then
      Result.Project :=
        (Positive'Value (Field (Payload, "project_id")),
         To_Unbounded_String (Field (Payload, "project")),
         To_Unbounded_String (Field (Payload, "project_path")),
         To_Unbounded_String (Field_Or (Payload, "quality_database", "")));
      Result.Baseline :=
        (Result.Project.Id, Positive'Value (Field (Payload, "run_id")),
         To_Unbounded_String (Field (Payload, "source")),
         To_Unbounded_String (Field (Payload, "policy")),
         To_Unbounded_String (Field (Payload, "toolchain")),
         To_Unbounded_String (Field_Or (Payload, "assessment", "")),
         To_Unbounded_String (Field (Payload, "snapshot")));
      return Result;
   end if;
   declare
      Plan_Row : constant Entity :=
        Required (Plans_Table, Positive (Revision.Parent_Id), "plan");
      Project_Row : constant Entity :=
        Required (Projects_Table, Positive (Plan_Row.Parent_Id), "project");
      Baseline_Row : constant Entity :=
        Required
          (Baselines_Table, Positive'Value (Field (Payload, "baseline_id")), "assessment baseline");
      Project_Data : constant String := S (Project_Row.Payload);
      Baseline_Data : constant String := S (Baseline_Row.Payload);
   begin
      Consume (S (Plan_Row.Kind), "plan identity");
      Consume (S (Plan_Row.State), "plan state");
      Consume (S (Plan_Row.Payload), "plan payload");
      Consume (S (Project_Row.Kind), "project reference identity");
      Consume (S (Project_Row.State), "project reference state");
      Consume (Project_Data, "project reference payload");
      Consume (S (Baseline_Row.Kind), "assessment baseline identity");
      Consume (S (Baseline_Row.State), "assessment baseline state");
      Consume (Baseline_Data, "assessment baseline payload");
      Result.Project :=
        (Positive'Value (Field (Project_Data, "quality_project_id")),
         To_Unbounded_String (Field (Project_Data, "name")),
         To_Unbounded_String (Field (Project_Data, "path")),
         To_Unbounded_String (Field (Project_Data, "quality_database")));
      Result.Baseline :=
        (Result.Project.Id, Positive'Value (S (Baseline_Row.Kind)),
         To_Unbounded_String (Field (Baseline_Data, "source")),
         To_Unbounded_String (Field (Baseline_Data, "policy")),
         To_Unbounded_String (Field (Baseline_Data, "toolchain")),
         To_Unbounded_String (Field_Or (Baseline_Data, "assessment", "")),
         To_Unbounded_String (Field (Baseline_Data, "snapshot")));
      if Baseline_Row.Parent_Id /= Project_Row.Id or else
        S (Plan_Row.Kind) /= S (Project_Row.Kind) or else
        S (Baseline_Row.State) /= "completed" or else
        Positive'Value (Field (Payload, "project_id")) /= Result.Project.Id or else
        Field (Payload, "project") /= To_String (Result.Project.Name) or else
        Field (Payload, "project_path") /= To_String (Result.Project.Path) or else
        Field_Or (Payload, "quality_database", "") /= To_String (Result.Project.Database_Id) or else
        Positive'Value (Field (Payload, "run_id")) /= Result.Baseline.Run_Id or else
        Field (Payload, "source") /= To_String (Result.Baseline.Source_Id) or else
        Field (Payload, "policy") /= To_String (Result.Baseline.Policy_Id) or else
        Field (Payload, "toolchain") /= To_String (Result.Baseline.Toolchain_Id) or else
        Field_Or (Payload, "assessment", "") /= To_String (Result.Baseline.Evidence_Id) or else
        Field (Payload, "snapshot") /= To_String (Result.Baseline.Snapshot_Id)
      then
         raise Data_Error with "stored plan provenance relationships are inconsistent";
      end if;
      return Result;
   end;
exception
   when Constraint_Error =>
      raise Data_Error with "stored plan provenance is malformed";
end Provenance_Of;
