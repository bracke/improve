with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded;
with Ada.Strings.Wide_Wide_Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
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
with Improve.Storage;
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

   type Storage_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Storage_Case;

   overriding function Name (Item : Storage_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_STORAGE_INDEXED_HISTORY"));

   overriding procedure Run_Test (Item : in out Storage_Case) is
      pragma Unreferenced (Item);
      Root  : constant String := "/tmp/improve_storage_indexed_history";
      Path  : constant String := Root & "/state.db";
      Store : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;
      Stored_Plan : Improve.Model.Plan_Revision;

      function Image (Value : Positive) return String is
        (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));
   begin
      Project_Tools.Files.Delete_Tree (Root);
      Ada.Directories.Create_Directory (Root);
      Plan.Project :=
        (Id          => 1,
         Name        => To_Unbounded_String ("scale"),
         Path        => To_Unbounded_String (Root),
         Database_Id => To_Unbounded_String (Root & "/quality.db"));
      Plan.Baseline :=
        (Project_Id   => 1,
         Run_Id       => 1,
         Source_Id    => To_Unbounded_String ("source"),
         Policy_Id    => To_Unbounded_String ("policy"),
         Toolchain_Id => To_Unbounded_String ("toolchain"),
         Snapshot_Id  => To_Unbounded_String ("snapshot"));
      Plan.Working_Source_Id := To_Unbounded_String ("working");
      Plan.Planner_Id := To_Unbounded_String ("planner");
      Plan.Review_Status := To_Unbounded_String ("not-required");
      for Index in 1 .. 5 loop
         Plan.Tasks.Append
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
      Improve.Storage.Open (Store, Path, Writable => True);
      for Revision in 1 .. 4 loop
         Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("scale revision " & Image (Revision)));
         declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan); begin
            Assert
              (not Saved.Existing and then Saved.Plan.Revision = Revision,
               "indexed scale history did not create the expected revision");
         end;
      end loop;
      declare Summaries : constant Improve.Storage.Summary_Vectors.Vector := Improve.Storage.List (Store, Plan.Project);
      begin
         Assert
           (Summaries.Length = 1 and then Summaries.First_Element.Revision = 4 and then
            Summaries.First_Element.Task_Count = 5,
            "indexed plan listing did not select the latest large revision");
      end;
      Stored_Plan := Improve.Storage.Load (Store, "PLAN-000001");
      declare
         Task_Ids : Improve.Model.UString_Vectors.Vector;
         Limits   : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
         Rejected : Boolean := False;
      begin
         Task_Ids.Append (Stored_Plan.Tasks (1).Id);
         Task_Ids.Append (Stored_Plan.Tasks (2).Id);
         Limits.Maximum_Tasks := 1;
         begin
            declare
               Operation : constant Positive :=
                 Improve.Storage.Begin_Publication (Store, Stored_Plan, Task_Ids, Limits);
               pragma Unreferenced (Operation);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "publication journal packed tasks before enforcing its configured limit");
      end;
      declare
         Mappings : Improve.Storage.Publication_Vectors.Vector;
         Evidence : Improve.Storage.Verification_Vectors.Vector;
         Limit_Rejected : Boolean := False;
         Read_Limit_Rejected : Boolean := False;
      begin
         begin
            declare
               Value : constant Improve.Model.Plan_Revision :=
                 Improve.Storage.Load
                   (Store, "PLAN-000001",
                    (Maximum_Findings     => 10,
                     Maximum_Tasks        => 1,
                     Maximum_Task_Details => 10,
                     Maximum_Task_Links   => 10,
                     Maximum_History      => 10,
                     Maximum_Text_Bytes   => 1_024));
               pragma Unreferenced (Value);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Read_Limit_Rejected := True;
         end;
         Assert (Read_Limit_Rejected, "plan reconstruction ignored its configured task limit");
         for Index in 1 .. 2 loop
            Mappings.Append
              (Improve.Storage.Publication_Record'
                 (Improve_Task_Id => Stored_Plan.Tasks (Index).Id,
                  Harness_Task_Id => To_Unbounded_String ("TASK-SCALE-" & Image (Index)),
                  Origin          => To_Unbounded_String ("improve:scale:" & Image (Index)),
                  Contract        => To_Unbounded_String ("contract-" & Image (Index)),
                  State           => To_Unbounded_String ("candidate"),
                  Plan_Revision   => Stored_Plan.Revision));
            Evidence.Append
              (Improve.Storage.Verification_Record'
                 (Scope                => Improve.Storage.Task_Evaluation,
                  Task_Id              => Stored_Plan.Tasks (Index).Id,
                  Plan_Revision        => Stored_Plan.Revision,
                  Contract_Fingerprint => To_Unbounded_String ("verification-" & Image (Index)),
                  Assessment_Id        => 1,
                  Outcome              => Improve.Model.Still_Failing,
                  Comparable           => True,
                  Explanation          => To_Unbounded_String ("indexed evidence")));
         end loop;
         Improve.Storage.Record_Publications (Store, To_String (Stored_Plan.Plan_Id), Mappings);
         Improve.Storage.Record_Verification (Store, To_String (Stored_Plan.Plan_Id), Evidence);
         Assert
           (Improve.Storage.Publications (Store, To_String (Stored_Plan.Plan_Id)).Length = 2 and then
            Improve.Storage.Verifications (Store, To_String (Stored_Plan.Plan_Id)).Length = 2,
            "indexed publication or verification history was not plan-scoped");
         declare
            Limits : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
            Publication_Rejected : Boolean := False;
            Verification_Rejected : Boolean := False;
         begin
            Limits.Maximum_Text_Bytes := 16;
            begin
               declare
                  Values : constant Improve.Storage.Publication_Vectors.Vector :=
                    Improve.Storage.Publications
                      (Store, To_String (Stored_Plan.Plan_Id), Limits => Limits);
                  pragma Unreferenced (Values);
               begin
                  null;
               end;
            exception
               when Improve.Data_Error => Publication_Rejected := True;
            end;
            begin
               declare
                  Values : constant Improve.Storage.Verification_Vectors.Vector :=
                    Improve.Storage.Verifications
                      (Store, To_String (Stored_Plan.Plan_Id), Limits => Limits);
                  pragma Unreferenced (Values);
               begin
                  null;
               end;
            exception
               when Improve.Data_Error => Verification_Rejected := True;
            end;
            Assert
              (Publication_Rejected and then Verification_Rejected,
               "history payload reads ignored configured byte limits");
         end;
         begin
            declare
               Values : constant Improve.Storage.Publication_Vectors.Vector :=
                 Improve.Storage.Publications (Store, To_String (Stored_Plan.Plan_Id), Maximum => 1);
               pragma Unreferenced (Values);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Limit_Rejected := True;
         end;
         Assert (Limit_Rejected, "indexed publication reads ignored their materialization limit");
      end;
      Improve.Storage.Close (Store);
      Downgrade_To_Version_2 (Path);
      Improve.Storage.Open (Store, Path, Writable => True);
      Assert
        (Improve.Storage.Publications (Store, To_String (Stored_Plan.Plan_Id)).Length = 2 and then
         Improve.Storage.Verifications (Store, To_String (Stored_Plan.Plan_Id)).Length = 2,
         "schema migration did not preserve indexed plan history");
      declare
         Migrated : constant Improve.Model.Plan_Revision :=
           Improve.Storage.Load_Task (Store, To_String (Stored_Plan.Tasks.First_Element.Id));
      begin
         Assert
           (Migrated.Revision = Stored_Plan.Revision,
            "schema migration did not build the historical task identity index");
      end;
      declare
         Large_Plan : Improve.Model.Plan_Revision := Plan;
         Large_Text : Unbounded_String;
         Limits     : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      begin
         Append (Large_Text, [1 .. 384 => 'x']);
         Large_Plan.Tasks (1).Goal := Large_Text;
         Large_Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("large approved revision"));
         declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Large_Plan); begin
            Limits.Maximum_Text_Bytes := 128;
            declare
               Rejected : Boolean := False;
            begin
               begin
                  Improve.Storage.Approve
                    (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits);
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "approval ignored its configured payload limit");
            end;
            Limits.Maximum_Text_Bytes := 1_024;
            Improve.Storage.Approve
              (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits);
            Assert
              (Improve.Storage.Is_Approved
                 (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits),
               "configured read limits were lost during approval validation");
            declare
               Task_Ids : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
            begin
               Task_Ids.Append (Saved.Plan.Tasks.First_Element.Id);
               Operation := Improve.Storage.Begin_Publication (Store, Saved.Plan, Task_Ids, Limits);
               Improve.Storage.Complete_Publication (Store, Operation);
               Assert
                 (Improve.Storage.Pending_Publications (Store, Limits => Limits).Is_Empty,
                  "configured read limits were lost during publication journaling");
            end;
         end;
      end;
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
   exception
      when others =>
         Improve.Storage.Close (Store);
         Project_Tools.Files.Delete_Tree (Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Storage_Case));
      return Result;
   end Suite;
end Improve_Storage_Test_Suite;
