with Ada.Containers;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded;
with Ada.Strings.Wide_Wide_Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Ada_Quality.Types;
with Database;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Improve;
with Improve.Model;
with Improve.Persistence_Records;
with Improve.Storage;
with Hostkit.Fs;
with Project_Tools.Files;

package body Improve_Storage_Test_Suite is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use AUnit.Assertions;
   use type Ada.Containers.Count_Type;
   use type Database.Status_Code;

   type Raw_Entity is record
      Id        : Positive;
      Parent_Id : Natural := 0;
      Kind      : Unbounded_Wide_Wide_String;
      State     : Unbounded_Wide_Wide_String;
      Payload   : Unbounded_Wide_Wide_String;
      Active    : Boolean := True;
      Table_Id  : Positive := 1;
   end record;

   function Physical_Key (Table, Id : Positive) return Positive is
     ((Table - 1) * 100_000_000 + Id);

   function To_Row (Value : Raw_Entity) return Database.Rows.Row is
      Result : Database.Rows.Row;
   begin
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Physical_Key (Value.Table_Id, Value.Id))));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Value.Table_Id)));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Value.Id)));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Value.Parent_Id)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.Kind)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.State)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Value.Payload)));
      Database.Rows.Append (Result, Database.Values.From_Boolean (Value.Active));
      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Raw_Entity is
     ((Id        => Positive (Database.Rows.Get (Row, 2).Int),
       Parent_Id => Natural (Database.Rows.Get (Row, 3).Int),
       Kind      => Database.Rows.Get (Row, 4).Text,
       State     => Database.Rows.Get (Row, 5).Text,
       Payload   => Database.Rows.Get (Row, 6).Text,
       Active    => Database.Rows.Get (Row, 7).Bool,
       Table_Id  => Positive (Database.Rows.Get (Row, 1).Int)));

   function Key_Of (Value : Raw_Entity) return Positive is (Physical_Key (Value.Table_Id, Value.Id));
   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));

   package Raw_Tables is new Database.Tables.Typed
     (Raw_Entity, Positive, To_Row, From_Row, Key_Of, Key_Value);

   function Raw_Schema return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String ("improve_records");
      Database.Schema.Add_Column (Result, "physical_id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (Result, "table_id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "parent_id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "kind", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "state", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "payload", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "active", Database.Types.Boolean_Value, False);
      return Result;
   end Raw_Schema;

   procedure Downgrade_To_Version_2 (Path : String) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Raw_Entity;
      Status : Database.Status.Result;

      procedure Clear_Parent (Table, Id : Positive) is
      begin
         Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (Table, Id), Row);
         Assert (Status.Code = Database.Status.Ok, "legacy row is missing");
         Row.Parent_Id := 0;
         Assert
           (Raw_Tables.Update (Tx, DB, Schema, Row).Code = Database.Status.Ok,
            "legacy parent could not be cleared");
      end Clear_Parent;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "state database could not be reopened for migration fixture");
      Database.Transactions.Begin_Write (DB, Tx);
      Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (1, 1), Row);
      Assert (Status.Code = Database.Status.Ok, "schema metadata is missing");
      Row.State := To_Unbounded_Wide_Wide_String ("2");
      Assert
        (Raw_Tables.Update (Tx, DB, Schema, Row).Code = Database.Status.Ok,
         "schema metadata could not be downgraded");
      for Id in 1 .. 2 loop
         Clear_Parent (10, Id);
         Clear_Parent (11, Id);
      end loop;
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         raise;
   end Downgrade_To_Version_2;

   procedure Corrupt_Revision (Path : String; Revision_Id : Positive) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Raw_Entity;
      Status : Database.Status.Result;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "state database could not be reopened for corruption fixture");
      Database.Transactions.Begin_Write (DB, Tx);
      Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (6, Revision_Id), Row);
      Assert (Status.Code = Database.Status.Ok, "revision fixture is missing");
      Row.Payload := To_Unbounded_Wide_Wide_String ("revision=broken");
      Assert
        (Raw_Tables.Update (Tx, DB, Schema, Row).Code = Database.Status.Ok,
         "revision fixture could not be corrupted");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         raise;
   end Corrupt_Revision;

   procedure Corrupt_Baseline_Parent
     (Path : String; Baseline_Id : Positive) is separate;

   procedure Replace_Row_Payload
     (Path    : String;
      Table   : Positive;
      Id      : Positive;
      Payload : String) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Raw_Entity;
      Status : Database.Status.Result;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for payload corruption");
      Database.Transactions.Begin_Write (DB, Tx);
      Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (Table, Id), Row);
      Assert (Status.Code = Database.Status.Ok, "payload corruption fixture row is missing");
      Row.Payload := To_Unbounded_Wide_Wide_String
        (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Payload));
      Assert
        (Raw_Tables.Update (Tx, DB, Schema, Row).Code = Database.Status.Ok,
         "fixture row payload could not be corrupted");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         raise;
   end Replace_Row_Payload;

   procedure Duplicate_Row
     (Path      : String;
      Table     : Positive;
      Source_Id : Positive;
      New_Id    : Positive) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Raw_Entity;
      Status : Database.Status.Result;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for duplicate fixture");
      Database.Transactions.Begin_Write (DB, Tx);
      Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (Table, Source_Id), Row);
      Assert (Status.Code = Database.Status.Ok, "duplicate fixture source row is missing");
      Row.Id := New_Id;
      Assert
        (Raw_Tables.Insert (Tx, DB, Schema, Row).Code = Database.Status.Ok,
         "duplicate fixture row could not be inserted");
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         raise;
   end Duplicate_Row;

   procedure Duplicate_Plan (Path : String; Task_Count : Positive) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Raw_Entity;
      Status : Database.Status.Result;

      procedure Clone
        (Table, Source_Id, New_Id, Parent_Id : Positive) is
      begin
         Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (Table, Source_Id), Row);
         Assert (Status.Code = Database.Status.Ok, "ambiguous-plan source row is missing");
         Row.Id := New_Id;
         Row.Parent_Id := Parent_Id;
         Assert
           (Raw_Tables.Insert (Tx, DB, Schema, Row).Code = Database.Status.Ok,
            "ambiguous-plan fixture row could not be inserted");
      end Clone;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for plan duplication");
      Database.Transactions.Begin_Write (DB, Tx);
      Clone (5, 1, 2, 1);
      Clone (6, 1, 2, 2);
      for Index in 1 .. Task_Count loop
         Clone (7, Index, 100 + Index, 2);
      end loop;
      Database.Transactions.Commit (Tx);
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         raise;
   end Duplicate_Plan;

   procedure Exhaust_Project_Identities (Path : String) is separate;

   procedure Insert_Unknown_Finding_Link
     (Path : String; Task_Row : Positive) is separate;

   procedure Insert_Duplicate_Task_Detail
     (Path : String; Task_Row : Positive) is separate;

   type Test_Id is
     (Invariant_Validation, Indexed_History, Ambiguous_Plans, Schema_Migration, Operational_Limits,
      Identity_Exhaustion, Corrupt_Links, Corrupt_Revision_Data,
      Corrupt_Task_Detail, Corrupt_Provenance, Corrupt_Persistence_Context);

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
      Limits    : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits) is
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
      Mappings : out Improve.Storage.Publication_Vectors.Vector;
      Evidence : out Improve.Storage.Verification_Vectors.Vector) is
   begin
      for Index in 1 .. 2 loop
         declare Contract : constant String :=
           Improve.Model.Effective_Task_Contract_Fingerprint
             (Stored, Stored.Tasks (Index).Id);
         begin
            Mappings.Append
              (Improve.Storage.Publication_Record'
                 (Improve_Task_Id => Stored.Tasks (Index).Id,
                  Harness_Task_Id => To_Unbounded_String ("TASK-SCALE-" & Image (Index)),
                  Origin          => To_Unbounded_String ("improve:scale:" & Image (Index)),
                  Contract        => To_Unbounded_String (Contract),
                  State           => To_Unbounded_String ("candidate"),
                  Plan_Revision   => Stored.Revision));
            Evidence.Append
              (Improve.Storage.Verification_Record'
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
   procedure Run_Indexed_History is separate;
   procedure Run_Ambiguous_Plans is separate;
   procedure Run_Schema_Migration is separate;
   procedure Run_Operational_Limits is separate;
   procedure Run_Identity_Exhaustion is separate;
   procedure Run_Corrupt_Links is separate;
   procedure Run_Corrupt_Revision_Data is separate;
   procedure Run_Corrupt_Task_Detail is separate;
   procedure Run_Corrupt_Provenance is separate;
   procedure Run_Corrupt_Persistence_Context is separate;

   procedure Run_Test (Item : in out Storage_Case) is
   begin
      case Item.Id is
         when Invariant_Validation => Run_Invariant_Validation;
         when Indexed_History => Run_Indexed_History;
         when Ambiguous_Plans => Run_Ambiguous_Plans;
         when Schema_Migration => Run_Schema_Migration;
         when Operational_Limits => Run_Operational_Limits;
         when Identity_Exhaustion => Run_Identity_Exhaustion;
         when Corrupt_Links => Run_Corrupt_Links;
         when Corrupt_Revision_Data => Run_Corrupt_Revision_Data;
         when Corrupt_Task_Detail => Run_Corrupt_Task_Detail;
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
