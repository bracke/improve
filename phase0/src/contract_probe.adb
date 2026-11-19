with Ada.Containers;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Model_Runner.Errors;
with Model_Runner.Framework.Configuration_Records;
with Model_Runner.Framework.Records;
with Model_Runner.Framework.Schemas;
with Model_Runner.Framework.Stores;
with Model_Runner.Framework.Tasks;

--  Executable Phase 0 proof of both external integration boundaries.
procedure Contract_Probe is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   Root    : constant String := Ada.Directories.Current_Directory;
   Scratch : constant String := "/tmp/improve_phase0_contract";
   DB_Path : constant String := Scratch & "/quality.db";
   Harness : constant String := Scratch & "/harness";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Check_Quality_Contract is
      Store   : Ada_Quality.Storage.Store;
      Session : Ada_Quality.Reporting.Session;
      Project : Positive;
      Run     : Positive;
      Value   : Assessment;
   begin
      Ada_Quality.Storage.Open (Store, DB_Path);
      Project := Ada_Quality.Storage.Add_Project (Store, Root);
      Run := Ada_Quality.Storage.Start_Assessment (Store, Project, "phase0-source", "phase0-policy");
      Value.Id := Run;
      Value.Project_Id := Project;
      Value.Project_Path := To_Unbounded_String (Root);
      Value.Source_Fingerprint := To_Unbounded_String ("phase0-source");
      Value.Policy_Fingerprint := To_Unbounded_String ("phase0-policy");
      Value.Toolchain_Fingerprint := To_Unbounded_String ("gnat-15.2.1");
      Value.Status := Assessment_Completed;
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'(Indicator  => Indicator,
             Execution  => Succeeded,
             Compliance => (if Indicator = STR_01 then Violation else Pass),
             Applicable => True,
             Summary     => To_Unbounded_String (if Indicator = STR_01 then "fixture violation" else "pass"),
             Evidence    => To_Unbounded_String ("phase0 contract evidence"),
             Measurement => (Kind => Boolean_Value, Boolean_Data => Indicator /= STR_01),
             Findings    => <>));
      end loop;
      declare
         Index : constant Positive := Value.Results.First_Index + Indicator_Id'Pos (STR_01);
         Item  : Indicator_Result := Value.Results (Index);
      begin
         Item.Compliance := Violation;
         Item.Summary := To_Unbounded_String ("fixture violation");
         Item.Measurement := (Kind => Boolean_Value, Boolean_Data => False);
         Item.Findings.Append
           (Finding'(Indicator    => STR_01,
             Rule         => To_Unbounded_String ("phase0.invalid-manifest"),
             Level        => High,
             Message      => To_Unbounded_String ("contract fixture violation"),
             Relative_Path => To_Unbounded_String ("alire.toml"),
             Line         => 1,
             Fingerprint  => To_Unbounded_String
               (Ada_Quality.Finding_Identity.Create
                  (STR_01, "phase0.invalid-manifest", "alire.toml", "contract fixture violation"))));
         Value.Results.Replace_Element (Index, Item);
      end;
      Require (Ada_Quality.Storage.Publish (Store, Value) = Run, "assessment publication changed its identity");
      Ada_Quality.Storage.Close (Store);

      Ada_Quality.Reporting.Open (Session, DB_Path);
      Require (Ada_Quality.Reporting.Projects (Session).Length = 1, "reporting did not expose the project");
      Require (Ada_Quality.Reporting.Runs (Session, Project).Length = 1, "reporting did not expose the run");
      declare
         Loaded : constant Ada_Quality.Reporting.Assessment_Record :=
           Ada_Quality.Reporting.Read_Assessment (Session, Run);
      begin
         Require (Loaded.Results.Length = 33, "reporting did not return all 33 indicators");
         Require (Loaded.Results.First_Element.Findings.Length = 1, "reporting lost the typed finding");
         Require (Ada_Quality.Reporting.Snapshot_Identity (Session)'Length = 24,
                  "reporting returned a malformed snapshot identity");
      end;
      Ada_Quality.Reporting.Close (Session);
   end Check_Quality_Contract;

   procedure Check_Harness_Contract is
      package Config renames Model_Runner.Framework.Configuration_Records;
      package Errors renames Model_Runner.Errors;
      package Records renames Model_Runner.Framework.Records;
      package Schemas renames Model_Runner.Framework.Schemas;
      package Stores renames Model_Runner.Framework.Stores;
      package Tasks renames Model_Runner.Framework.Tasks;

      Store    : Stores.Store;
      Initial  : Stores.Transaction;
      Resolved : Records.Item := Records.Create (Schemas.Configuration_Schema, 1, "CONFIG", 1);
      Change   : Stores.Transaction;
      Fields   : Tasks.Field_Map;
      Id       : Ada.Strings.Unbounded.Unbounded_String;
      Status   : Errors.Error_Info;
   begin
      Ada.Directories.Create_Directory (Harness);
      Records.Set (Resolved, "template_id", "improve-contract");
      Records.Set (Resolved, "template_version", "1");
      Records.Set (Resolved, "template_fingerprint", "phase0");
      Records.Set (Resolved, "template_origin", "Phase 0 contract probe");
      Records.Set (Resolved, "template_order", "improve-contract");
      Records.Set (Resolved, "task_kind.remediation", "acceptance, notes?");
      Records.Set (Resolved, "configuration_fingerprint", Config.Fingerprint (Resolved));
      Stores.Put (Initial, Model_Runner.Framework.Config_Area, "resolved", Resolved);
      Stores.Create (Store, Harness, "Improve contract", Status, Initial);
      Require (Errors.Is_Ok (Status), "model_runner could not initialize the fixture project");
      Require (Tasks.Kinds (Store).Contains ("remediation"), "model_runner did not expose the configured task kind");

      Fields.Include ("title", "Repair the contract fixture");
      Fields.Include ("kind", "remediation");
      Fields.Include ("acceptance", "The Phase 0 contract probe passes.");
      Fields.Include ("notes", "Ada Quality finding phase0-finding");
      Tasks.Create (Store, Change, Fields, "improve", "improve:phase0-finding", Id, Status);
      Require (Errors.Is_Ok (Status), "model_runner refused the native Improve task");
      Stores.Commit (Store, Change, Status);
      Require (Errors.Is_Ok (Status), "model_runner could not commit the native Improve task");
      Require (Tasks.State_Of (Store, To_String (Id)) = "candidate", "published task was not a candidate");
      Stores.Close (Store);
   end Check_Harness_Contract;
begin
   if Ada.Directories.Exists (Scratch) then
      Ada.Directories.Delete_Tree (Scratch);
   end if;
   Ada.Directories.Create_Directory (Scratch);
   Check_Quality_Contract;
   Check_Harness_Contract;
   Ada.Text_IO.Put_Line ("Phase 0 contracts passed");
exception
   when others =>
      if Ada.Directories.Exists (Scratch) then
         Ada.Directories.Delete_Tree (Scratch);
      end if;
      raise;
end Contract_Probe;

