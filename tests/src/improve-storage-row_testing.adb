with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Predicates;
with Database.Schema;
with Database.Values;
with Improve.Storage.Raw_Testing;
with Improve.Storage.Test_Fixtures;
with Improve.Storage_Codec;

package body Improve.Storage.Row_Testing is
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage.Test_Fixtures;
   use type Database.Predicates.Predicate;

   function Summary_Row_Bytes (Path : String; Revision_Id : Positive) return Positive is
      Item     : Session;
      Schema   : constant Database.Schema.Table_Schema := Raw_Schema;
      Revision : Persistence_Entity;
      Plan     : Persistence_Entity;
      Project  : Persistence_Entity;
      Baseline : Persistence_Entity;
      Total    : Natural := 0;

      function Text (Value : Unbounded_Wide_Wide_String) return String is
        (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
           (To_Wide_Wide_String (Value)));

      procedure Add (Row : Persistence_Entity) is
      begin
         Total := Total +
           Text (Row.Kind)'Length + Text (Row.State)'Length +
           Text (Row.Payload)'Length;
      end Add;

      procedure Find_Row
        (Table, Id : Positive;
         Row       : out Persistence_Entity) is
      begin
         Check
           (Persistence_Entity_Tables.Find
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Table, Id), Row),
            "summary fixture row is missing");
      end Find_Row;
   begin
      Open_Read (Item, Path);
      Find_Row (Revisions_Table, Revision_Id, Revision);
      Find_Row (Plans_Table, Positive (Revision.Parent_Id), Plan);
      Find_Row (Projects_Table, Positive (Plan.Parent_Id), Project);
      Find_Row
        (Baselines_Table,
         Positive'Value
           (Improve.Storage_Codec.Field
              (Text (Revision.Payload), "baseline_id")),
         Baseline);
      Add (Revision);
      Add (Plan);
      Add (Project);
      Add (Baseline);
      declare
         Predicate : constant Database.Predicates.Predicate :=
           Database.Predicates.Column_Equals
             (1, Database.Values.From_Integer (Integer (Tasks_Table))) and
           Database.Predicates.Column_Equals
             (3, Database.Values.From_Integer (Integer (Revision_Id)));
         Cursor : Persistence_Entity_Tables.Cursor;
      begin
         Check
           (Persistence_Entity_Tables.Scan
              (Item.Tx, Item.DB, Schema, Predicate, Cursor),
            "summary task rows could not be scanned");
         while Persistence_Entity_Tables.Has_Element (Cursor) loop
            Add (Persistence_Entity_Tables.Element (Cursor));
            Check
              (Persistence_Entity_Tables.Next
                 (Item.Tx, Item.DB, Schema, Predicate, Cursor),
               "summary task rows could not be advanced");
         end loop;
      end;
      Close (Item);
      return Positive (Total);
   end Summary_Row_Bytes;

   procedure Corrupt_Revision (Path : String; Revision_Id : Positive) is
   begin
      Replace_Row_Payload
        (Path, Revisions_Table, Revision_Id, "revision=broken");
   end Corrupt_Revision;

   procedure Corrupt_Baseline_Parent
     (Path        : String;
      Baseline_Id : Positive) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Baselines_Table, Baseline_Id), Row),
         "baseline fixture is missing");
      Row.Parent_Id := 99_999_999;
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "baseline fixture could not be corrupted");
      Commit (Item);
   end Corrupt_Baseline_Parent;

   procedure Replace_Row_Payload
     (Path    : String;
      Table   : Positive;
      Id      : Positive;
      Payload : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Table, Id), Row),
         "payload corruption fixture row is missing");
      Row.Payload := To_Unbounded_Wide_Wide_String
        (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Payload));
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "fixture row payload could not be corrupted");
      Commit (Item);
   end Replace_Row_Payload;

   procedure Replace_Row_State
     (Path  : String;
      Table : Positive;
      Id    : Positive;
      State : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Table, Id), Row),
         "state corruption fixture row is missing");
      Row.State := To_Unbounded_Wide_Wide_String
        (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (State));
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "fixture row state could not be corrupted");
      Commit (Item);
   end Replace_Row_State;

   procedure Deactivate_Row (Path : String; Table, Id : Positive) is
   begin
      Improve.Storage.Raw_Testing.Deactivate_Row (Path, Table, Id);
   end Deactivate_Row;

   procedure Append_Task_Payload_Field
     (Path     : String;
      Task_Row : Positive;
      Name     : String;
      Value    : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Tasks_Table, Task_Row), Row),
         "task fixture is missing");
      Row.Payload := To_Unbounded_Wide_Wide_String
        (To_Wide_Wide_String (Row.Payload) & Wide_Wide_Character'Val (10) &
         Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode
           (Improve.Storage_Codec.Pair (Name, Value)));
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "task fixture payload could not be extended");
      Commit (Item);
   end Append_Task_Payload_Field;

   procedure Duplicate_Row
     (Path      : String;
      Table     : Positive;
      Source_Id : Positive;
      New_Id    : Positive) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Table, Source_Id), Row),
         "duplicate fixture source row is missing");
      Row.Id := New_Id;
      Check
        (Persistence_Entity_Tables.Insert (Item.Tx, Item.DB, Schema, Row),
         "duplicate fixture row could not be inserted");
      Commit (Item);
   end Duplicate_Row;

   procedure Duplicate_Plan (Path : String; Task_Count : Positive) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;

      procedure Clone
        (Table, Source_Id, New_Id, Parent_Id : Positive) is
      begin
         Check
           (Persistence_Entity_Tables.Find
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Table, Source_Id), Row),
            "ambiguous-plan source row is missing");
         Row.Id := New_Id;
         Row.Parent_Id := Parent_Id;
         Check
           (Persistence_Entity_Tables.Insert (Item.Tx, Item.DB, Schema, Row),
            "ambiguous-plan fixture row could not be inserted");
      end Clone;
   begin
      Open_Write (Item, Path);
      Clone (Plans_Table, 1, 2, 1);
      Clone (Revisions_Table, 1, 2, 2);
      for Index in 1 .. Task_Count loop
         Clone (Tasks_Table, Index, 100 + Index, 2);
      end loop;
      Commit (Item);
   end Duplicate_Plan;

   procedure Insert_Unknown_Finding_Link
     (Path     : String;
      Task_Row : Positive) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : constant Persistence_Entity :=
        (Id        => 1,
         Parent_Id => Task_Row,
         Kind      => To_Unbounded_Wide_Wide_String ("unknown-finding"),
         State     => To_Unbounded_Wide_Wide_String ("linked"),
         Payload   => Null_Unbounded_Wide_Wide_String,
         Active    => True,
         Table_Id  => Task_Findings_Table);
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Insert (Item.Tx, Item.DB, Schema, Row),
         "unknown finding-link fixture could not be inserted");
      Commit (Item);
   end Insert_Unknown_Finding_Link;

   procedure Insert_Duplicate_Task_Detail
     (Path     : String;
      Task_Row : Positive) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : constant Persistence_Entity :=
        (Id        => 99_000_000,
         Parent_Id => Task_Row,
         Kind      => To_Unbounded_Wide_Wide_String ("goal"),
         State     => To_Unbounded_Wide_Wide_String ("value"),
         Payload   => To_Unbounded_Wide_Wide_String
           ("conflicting persisted goal"),
         Active    => True,
         Table_Id  => Task_Details_Table);
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Insert (Item.Tx, Item.DB, Schema, Row),
         "duplicate task-detail fixture could not be inserted");
      Commit (Item);
   end Insert_Duplicate_Task_Detail;
end Improve.Storage.Row_Testing;
