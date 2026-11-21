with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Catalog;
with Database.Predicates;
with Database.Schema;
with Database.Status;
with Database.Values;
with Improve.Storage.Test_Fixtures;

package body Improve.Storage.Schema_Testing is
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage.Test_Fixtures;

   procedure Delete_Table_Rows
     (Item    : in out Session;
      Schema  : Database.Schema.Table_Schema;
      Table   : Positive;
      Context : String) is
      package Id_Vectors is new Ada.Containers.Vectors (Positive, Positive);
      Predicate : constant Database.Predicates.Predicate :=
        Database.Predicates.Column_Equals
          (1, Database.Values.From_Integer (Integer (Table)));
      Cursor : Persistence_Entity_Tables.Cursor;
      Ids    : Id_Vectors.Vector;
   begin
      Check
        (Persistence_Entity_Tables.Scan
           (Item.Tx, Item.DB, Schema, Predicate, Cursor),
         Context & " rows could not be scanned");
      while Persistence_Entity_Tables.Has_Element (Cursor) loop
         Ids.Append (Persistence_Entity_Tables.Element (Cursor).Id);
         Check
           (Persistence_Entity_Tables.Next
              (Item.Tx, Item.DB, Schema, Predicate, Cursor),
            Context & " rows could not be advanced");
      end loop;
      for Id of Ids loop
         Check
           (Persistence_Entity_Tables.Delete
              (Item.Tx, Item.DB, Schema, Persistence_Physical_Key (Table, Id)),
            Context & " row could not be removed");
      end loop;
   end Delete_Table_Rows;

   procedure Create_Foreign_Database (Path : String) is
      Item : Session;
   begin
      Create (Item, Path);
      Close (Item);
   end Create_Foreign_Database;

   function Has_Improve_Table (Path : String) return Boolean is
      Item   : Session;
      Schema : Database.Schema.Table_Schema;
      Status : Database.Status.Result;
   begin
      Open_Read_Only (Item, Path);
      Status := Database.Catalog.Find_By_Name
        (Database.Catalog_State_Key (Item.DB), "improve_records", Schema);
      Close (Item);
      return Database.Status.Is_Ok (Status);
   end Has_Improve_Table;

   procedure Corrupt_Schema_Ownership (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Schema_Metadata_Table, 1), Row),
         "schema metadata is missing");
      Row.Kind := To_Unbounded_Wide_Wide_String ("foreign");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "schema ownership metadata could not be corrupted");
      Commit (Item);
   end Corrupt_Schema_Ownership;

   procedure Downgrade_To_Version_2 (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;

      procedure Clear_Parent (Table, Id : Positive) is
      begin
         Check
           (Persistence_Entity_Tables.Find
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Table, Id), Row),
            "legacy row is missing");
         Row.Parent_Id := 0;
         Check
           (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
            "legacy parent could not be cleared");
      end Clear_Parent;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema, Persistence_Physical_Key (1, 1), Row),
         "schema metadata is missing");
      Row.State := To_Unbounded_Wide_Wide_String ("2");
      Row.Payload := To_Unbounded_Wide_Wide_String
        ("created_by=improve" & Wide_Wide_Character'Val (10) &
         "logical_tables=schema_metadata,projects,assessment_baselines,finding_references,plans," &
         "plan_revisions,remediation_tasks,task_finding_links,task_dependencies,publications," &
         "verification_records,operations");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "schema metadata could not be downgraded");
      for Id in 2 .. Logical_Table_Count loop
         Check
           (Persistence_Entity_Tables.Delete
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Schema_Metadata_Table, Id)),
            "logical identity counter could not be removed");
      end loop;
      Delete_Table_Rows
        (Item, Schema, Task_Identities_Table, "future task identity");
      for Id in 1 .. 2 loop
         Clear_Parent (Publications_Table, Id);
         Clear_Parent (Verifications_Table, Id);
      end loop;
      Commit (Item);
   end Downgrade_To_Version_2;

   procedure Downgrade_To_Version_3 (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Schema_Metadata_Table, 1), Row),
         "schema metadata is missing");
      Row.State := To_Unbounded_Wide_Wide_String ("3");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "schema metadata could not be downgraded");
      Delete_Table_Rows
        (Item, Schema, Task_Identities_Table, "future task identity");
      Check
        (Persistence_Entity_Tables.Delete
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key
              (Schema_Metadata_Table, Task_Identities_Table)),
         "future task identity counter could not be removed");
      Commit (Item);
   end Downgrade_To_Version_3;

   procedure Downgrade_To_Version_6 (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Schema_Metadata_Table, 1), Row),
         "schema metadata is missing");
      Row.State := To_Unbounded_Wide_Wide_String ("6");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "schema metadata could not be downgraded");
      for Id in 2 .. Logical_Table_Count loop
         Check
           (Persistence_Entity_Tables.Delete
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Schema_Metadata_Table, Id)),
            "logical identity counter could not be removed");
      end loop;
      Commit (Item);
   end Downgrade_To_Version_6;

   procedure Downgrade_To_Version_7 (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Schema_Metadata_Table, 1), Row),
         "schema metadata is missing");
      Row.State := To_Unbounded_Wide_Wide_String ("7");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "schema metadata could not be downgraded");
      Commit (Item);
   end Downgrade_To_Version_7;
end Improve.Storage.Schema_Testing;
