with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Ada_Quality.Types;
with Database.Fault_Injection;
with Improve;
with Improve.Model;
with Improve.Persistence_Records;
with Improve.State;
with Improve.Storage;
with Improve.Storage.Identity_Testing;
with Improve.Storage.Lifecycle_Testing;
with Improve.Storage.Row_Testing;
with Improve.Storage.Schema_Testing;
with Improve.Storage_Codec;
with Hostkit.Fs;
with Project_Tools.Files;

package body Improve_Storage_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Ada.Containers.Count_Type;

   procedure Downgrade_To_Version_2 (Path : String)
     renames Improve.Storage.Schema_Testing.Downgrade_To_Version_2;
   procedure Downgrade_To_Version_3 (Path : String)
     renames Improve.Storage.Schema_Testing.Downgrade_To_Version_3;
   procedure Create_Foreign_Database (Path : String)
     renames Improve.Storage.Schema_Testing.Create_Foreign_Database;
   function Has_Improve_Table (Path : String) return Boolean
     renames Improve.Storage.Schema_Testing.Has_Improve_Table;
   procedure Corrupt_Schema_Ownership (Path : String)
     renames Improve.Storage.Schema_Testing.Corrupt_Schema_Ownership;
   procedure Downgrade_To_Version_6 (Path : String)
     renames Improve.Storage.Schema_Testing.Downgrade_To_Version_6;
   function Identity_Counter_State (Path : String) return String
     renames Improve.Storage.Identity_Testing.Identity_Counter_State;
   function Task_Identity_Counter_Value (Path : String) return String
     renames Improve.Storage.Identity_Testing.Task_Identity_Counter_Value;
   procedure Corrupt_Revision (Path : String; Revision_Id : Positive)
     renames Improve.Storage.Row_Testing.Corrupt_Revision;
   procedure Corrupt_Baseline_Parent (Path : String; Baseline_Id : Positive)
     renames Improve.Storage.Row_Testing.Corrupt_Baseline_Parent;
   procedure Replace_Row_Payload (Path : String; Table, Id : Positive; Payload : String)
     renames Improve.Storage.Row_Testing.Replace_Row_Payload;
   procedure Replace_Row_State (Path : String; Table, Id : Positive; State : String)
     renames Improve.Storage.Row_Testing.Replace_Row_State;
   procedure Deactivate_Row (Path : String; Table, Id : Positive)
     renames Improve.Storage.Row_Testing.Deactivate_Row;
   procedure Append_Task_Payload_Field (Path : String; Task_Row : Positive; Name, Value : String)
     renames Improve.Storage.Row_Testing.Append_Task_Payload_Field;
   function Summary_Row_Bytes (Path : String; Revision_Id : Positive) return Positive
     renames Improve.Storage.Row_Testing.Summary_Row_Bytes;
   procedure Duplicate_Row (Path : String; Table, Source_Id, New_Id : Positive)
     renames Improve.Storage.Row_Testing.Duplicate_Row;
   procedure Duplicate_Plan (Path : String; Task_Count : Positive)
     renames Improve.Storage.Row_Testing.Duplicate_Plan;

   procedure Exhaust_Project_Identities (Path : String)
     renames Improve.Storage.Identity_Testing.Exhaust_Project_Identities;

   procedure Insert_Unknown_Finding_Link (Path : String; Task_Row : Positive)
     renames Improve.Storage.Row_Testing.Insert_Unknown_Finding_Link;

   procedure Insert_Duplicate_Task_Detail (Path : String; Task_Row : Positive)
     renames Improve.Storage.Row_Testing.Insert_Duplicate_Task_Detail;

   type Test_Id is
     (Invariant_Validation, Lifecycle_Failures, Indexed_History, Durable_Allocation,
      Ambiguous_Plans, Schema_Migration, Operational_Limits,
      Identity_Exhaustion, Interleaved_History_Validation, Corrupt_Links, Corrupt_Revision_Data,
      Corrupt_Task_Detail, Persisted_Content_Integrity, Previous_Task_Validation,
      Inactive_Persistence_Row, Corrupt_Provenance, Corrupt_Persistence_Context);

   type Storage_Case (Id : Test_Id) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Storage_Case;

   overriding procedure Run_Test (Item : in out Storage_Case);
   overriding function Name (Item : Storage_Case) return AUnit.Message_String;

   function Name (Item : Storage_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_STORAGE_" & Test_Id'Image (Item.Id)));

   function Image (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   function Fixture (Root : String) return Improve.Model.Plan_Revision is
      Result : Improve.Model.Plan_Revision;
   begin
      Result.Project :=
        (Id          => 1,
         Name        => To_Unbounded_String ("scale"),
         Path        => To_Unbounded_String (Root),
         Database_Id => To_Unbounded_String (Root & "/quality.db"));
      Result.Baseline :=
        (Project_Id   => 1,
         Run_Id       => 1,
         Source_Id    => To_Unbounded_String ("source"),
         Policy_Id    => To_Unbounded_String ("policy"),
         Toolchain_Id => To_Unbounded_String ("toolchain"),
         Evidence_Id  => To_Unbounded_String ("assessment"),
         Snapshot_Id  => To_Unbounded_String ("snapshot"));
      Result.Working_Source_Id := To_Unbounded_String ("working");
      Result.Planner_Id := To_Unbounded_String ("planner");
      Result.Review_Status := To_Unbounded_String ("not-required");
      for Index in 1 .. 5 loop
         Result.Tasks.Append
           (Improve.Model.Task_Specification'
              (Id              => To_Unbounded_String ("DRAFT-" & Image (Index)),
               Title           => To_Unbounded_String ("Indexed task " & Image (Index)),
               Category        => To_Unbounded_String ("remediation"),
               Goal            => To_Unbounded_String ("Exercise indexed revision persistence"),
               Problem         => To_Unbounded_String ("Historical task lookup must remain bounded"),
               Evidence        => To_Unbounded_String ("storage scale fixture"),
               Scope           => To_Unbounded_String ("task " & Image (Index)),
               Out_Of_Scope    => To_Unbounded_String ("unrelated tasks"),
               Requirements    => To_Unbounded_String ("none"),
               Acceptance      => To_Unbounded_String ("indexed persistence succeeds"),
               Verification    => To_Unbounded_String ("load the stored revision"),
               Requires_Review => False,
               others          => <>));
      end loop;
      return Result;
   end Fixture;

   procedure Seed
     (Store     : in out Improve.Storage.Store;
      Plan      : in out Improve.Model.Plan_Revision;
      Revisions : Positive;
      Stored    : out Improve.Model.Plan_Revision;
      Limits    : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits) is
   begin
      for Revision in 1 .. Revisions loop
         Plan.Fingerprint := To_Unbounded_String
           (Improve.Stable_Digest ("scale revision " & Image (Revision)));
         declare Saved : constant Improve.Storage.Save_Result :=
           Improve.Storage.Save (Store, Plan, Limits);
         begin
            Assert
              (not Saved.Existing and then Saved.Plan.Revision = Revision,
               "indexed history did not create the expected revision");
         end;
      end loop;
      Stored := Improve.Storage.Load (Store, "PLAN-000001", Limits);
   end Seed;

   procedure History_Records
     (Stored   : Improve.Model.Plan_Revision;
      Mappings : out Improve.State.Publication_Vectors.Vector;
      Evidence : out Improve.State.Verification_Vectors.Vector) is
   begin
      for Index in 1 .. 2 loop
         declare Contract : constant String :=
           Improve.Model.Effective_Task_Contract_Fingerprint
             (Stored, Stored.Tasks (Index).Id);
         begin
            Mappings.Append
              (Improve.State.Publication_Record'
                 (Improve_Task_Id => Stored.Tasks (Index).Id,
                  Harness_Task_Id => To_Unbounded_String ("TASK-SCALE-" & Image (Index)),
                  Origin          => To_Unbounded_String ("improve:scale:" & Image (Index)),
                  Contract        => To_Unbounded_String (Contract),
                  State           => To_Unbounded_String ("candidate"),
                  Plan_Revision   => Stored.Revision));
            Evidence.Append
              (Improve.State.Verification_Record'
                 (Scope                => Improve.Model.Task_Evaluation,
                  Task_Id              => Stored.Tasks (Index).Id,
                  Plan_Revision        => Stored.Revision,
                  Contract_Fingerprint => To_Unbounded_String (Contract),
                  Assessment_Id        => 1,
                  Outcome              => Improve.Model.Still_Failing,
                  Comparable           => True,
                  Explanation          => To_Unbounded_String ("indexed evidence")));
         end;
      end loop;
   end History_Records;

   procedure Run_Invariant_Validation is separate;
   procedure Run_Lifecycle_Failures is separate;
   procedure Run_Indexed_History is separate;
   procedure Run_Durable_Allocation is separate;
   procedure Run_Ambiguous_Plans is separate;
   procedure Run_Schema_Migration is separate;
   procedure Run_Operational_Limits is separate;
   procedure Run_Identity_Exhaustion is separate;
   procedure Run_Interleaved_History_Validation is separate;
   procedure Run_Corrupt_Links is separate;
   procedure Run_Corrupt_Revision_Data is separate;
   procedure Run_Corrupt_Task_Detail is separate;
   procedure Run_Persisted_Content_Integrity is separate;
   procedure Run_Previous_Task_Validation is separate;
   procedure Run_Inactive_Persistence_Row is separate;
   procedure Run_Corrupt_Provenance is separate;
   procedure Run_Corrupt_Persistence_Context is separate;

   procedure Run_Test (Item : in out Storage_Case) is
   begin
      case Item.Id is
         when Invariant_Validation => Run_Invariant_Validation;
         when Lifecycle_Failures => Run_Lifecycle_Failures;
         when Indexed_History => Run_Indexed_History;
         when Durable_Allocation => Run_Durable_Allocation;
         when Ambiguous_Plans => Run_Ambiguous_Plans;
         when Schema_Migration => Run_Schema_Migration;
         when Operational_Limits => Run_Operational_Limits;
         when Identity_Exhaustion => Run_Identity_Exhaustion;
         when Interleaved_History_Validation => Run_Interleaved_History_Validation;
         when Corrupt_Links => Run_Corrupt_Links;
         when Corrupt_Revision_Data => Run_Corrupt_Revision_Data;
         when Corrupt_Task_Detail => Run_Corrupt_Task_Detail;
         when Persisted_Content_Integrity => Run_Persisted_Content_Integrity;
         when Previous_Task_Validation => Run_Previous_Task_Validation;
         when Inactive_Persistence_Row => Run_Inactive_Persistence_Row;
         when Corrupt_Provenance => Run_Corrupt_Provenance;
         when Corrupt_Persistence_Context => Run_Corrupt_Persistence_Context;
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Id in Test_Id loop
         Result.Add_Test (Case_Access'(new Storage_Case (Id)));
      end loop;
      return Result;
   end Suite;
end Improve_Storage_Test_Suite;
