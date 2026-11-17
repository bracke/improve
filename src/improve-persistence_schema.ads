with Ada.Strings.Wide_Wide_Unbounded;
with Database.Rows;
with Database.Schema;
with Database.Tables;
with Database.Values;

--  Physical namespace and row mapping assigned to Improve persistence.
private package Improve.Persistence_Schema is
   --  Implementation-level logical namespaces and collision-free physical key mapping.

   Logical_Table_Count : constant := 14;
   --  Number of stable logical namespaces in the Improve state schema.

   Schema_Metadata_Table   : constant Positive := 1;
   --  Schema manifest and identity-counter namespace.
   Projects_Table          : constant Positive := 2;
   --  Database-qualified project references.
   Baselines_Table         : constant Positive := 3;
   --  Immutable assessment baselines.
   Findings_Table          : constant Positive := 4;
   --  Normalized finding references.
   Plans_Table             : constant Positive := 5;
   --  Stable logical plans.
   Revisions_Table         : constant Positive := 6;
   --  Immutable plan revisions.
   Tasks_Table             : constant Positive := 7;
   --  Revision-owned remediation tasks.
   Task_Findings_Table     : constant Positive := 8;
   --  Task-to-finding links.
   Task_Dependencies_Table : constant Positive := 9;
   --  Task prerequisite links.
   Publications_Table      : constant Positive := 10;
   --  Native harness publication mappings.
   Verifications_Table     : constant Positive := 11;
   --  Independent quality verification evidence.
   Operations_Table        : constant Positive := 12;
   --  Approval and publication journal events.
   Task_Details_Table      : constant Positive := 13;
   --  Large normalized task-contract fields.
   Task_Identities_Table   : constant Positive := 14;
   --  Logical task history index.

   Namespace_Stride   : constant Positive := 100_000_000;
   --  Physical primary-key range reserved for each logical namespace.
   Maximum_Logical_Id : constant Positive := Namespace_Stride;
   --  Greatest logical row identity representable in one namespace.

   Physical_Key_Position : constant Natural := 0;
   Table_Id_Position     : constant Natural := 1;
   Id_Position           : constant Natural := 2;
   Parent_Id_Position    : constant Natural := 3;
   Kind_Position         : constant Natural := 4;
   State_Position        : constant Natural := 5;
   Payload_Position      : constant Natural := 6;
   Active_Position       : constant Natural := 7;
   --  Stable physical row positions shared by canonical mapping and controlled corruption tests.

   function Logical_Table_List return String;
   --  Return the stable comma-separated logical namespace manifest.
   --  @return Comma-separated namespace names in table order.
   function Physical_Key (Table, Id : Positive) return Positive;
   --  Encode a logical namespace and row identity as one physical primary key.
   --  @param Table Logical namespace identity.
   --  @param Id Logical row identity within Table.
   --  @return Collision-free physical primary key.

   type Entity is record
      Id        : Positive;
      Parent_Id : Natural := 0;
      Kind      : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      State     : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Payload   : Ada.Strings.Wide_Wide_Unbounded.Unbounded_Wide_Wide_String;
      Active    : Boolean := True;
      Table_Id  : Positive := 1;
   end record;
   --  One typed row in the shared physical Improve table.
   --  @field Id Logical identity inside Table_Id.
   --  @field Parent_Id Optional owning logical identity.
   --  @field Kind Indexed identity or category.
   --  @field State Indexed lifecycle or value classification.
   --  @field Payload Length-delimited encoded record data.
   --  @field Active Reserved lifecycle marker; every readable Improve row must be active.
   --  @field Table_Id Logical namespace containing the row.

   function To_Row (Item : Entity) return Database.Rows.Row;
   --  Encode one canonical entity as a database row.
   --  @param Item Entity to encode.
   --  @return Canonical physical database row.
   function From_Row (Row : Database.Rows.Row) return Entity;
   --  Decode one database row as a canonical entity.
   --  @param Row Physical database row to decode.
   --  @return Validated canonical entity.
   function Key_Of (Item : Entity) return Positive;
   --  Return the entity's collision-free physical primary key.
   --  @param Item Entity whose key is requested.
   --  @return Collision-free physical primary key.
   function Key_Value (Key : Positive) return Database.Values.Value;
   --  Encode a physical primary key as a database value.
   --  @param Key Physical primary key.
   --  @return Database value containing Key.

   package Entity_Tables is new Database.Tables.Typed
     (Entity, Positive, To_Row, From_Row, Key_Of, Key_Value);
   --  Canonical typed table access used by the persistence facade.

   function New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema;
   --  Return the canonical shared-table schema.
   --  @param Name Physical table name.
   --  @return Canonical shared-table schema.
end Improve.Persistence_Schema;
