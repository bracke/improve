with Ada.Strings.Unbounded;
with Database.Types;

package body Improve.Persistence_Schema is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;

   Table_Names : constant array (Positive range 1 .. Logical_Table_Count) of access constant String :=
     [new String'("schema_metadata"), new String'("projects"),
      new String'("assessment_baselines"), new String'("finding_references"),
      new String'("plans"), new String'("plan_revisions"),
      new String'("remediation_tasks"), new String'("task_finding_links"),
      new String'("task_dependencies"), new String'("publications"),
      new String'("verification_records"), new String'("operations"),
      new String'("task_details"), new String'("task_identities")];

   function Logical_Table_List return String is
      Result : Unbounded_String;
   begin
      for Table in Table_Names'Range loop
         if Table > Table_Names'First then
            Append (Result, ",");
         end if;
         Append (Result, Table_Names (Table).all);
      end loop;
      return To_String (Result);
   end Logical_Table_List;

   function Physical_Key (Table, Id : Positive) return Positive is
   begin
      if Table > Logical_Table_Count then
         raise Data_Error with "stored namespace identity is outside the Improve schema";
      elsif Id > Maximum_Logical_Id then
         raise Data_Error with "Improve logical identity space is exhausted";
      end if;
      return (Table - 1) * Namespace_Stride + Id;
   end Physical_Key;

   function To_Row (Item : Entity) return Database.Rows.Row is
      Result : Database.Rows.Row;

      procedure Append (Position : Natural; Value : Database.Values.Value) is
      begin
         if Database.Rows.Column_Count (Result) /= Position then
            raise Program_Error with "Improve physical row positions are inconsistent";
         end if;
         Database.Rows.Append (Result, Value);
      end Append;
   begin
      Append
        (Physical_Key_Position,
         Database.Values.From_Integer (Integer (Physical_Key (Item.Table_Id, Item.Id))));
      Append (Table_Id_Position, Database.Values.From_Integer (Integer (Item.Table_Id)));
      Append (Id_Position, Database.Values.From_Integer (Integer (Item.Id)));
      Append (Parent_Id_Position, Database.Values.From_Integer (Integer (Item.Parent_Id)));
      Append (Kind_Position, Database.Values.From_Text (To_Wide_Wide_String (Item.Kind)));
      Append (State_Position, Database.Values.From_Text (To_Wide_Wide_String (Item.State)));
      Append (Payload_Position, Database.Values.From_Text (To_Wide_Wide_String (Item.Payload)));
      Append (Active_Position, Database.Values.From_Boolean (Item.Active));
      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Entity is
      Stored_Key : constant Positive := Positive (Database.Rows.Get (Row, Physical_Key_Position).Int);
      Table      : constant Positive := Positive (Database.Rows.Get (Row, Table_Id_Position).Int);
      Id         : constant Positive := Positive (Database.Rows.Get (Row, Id_Position).Int);
      Active     : constant Boolean := Database.Rows.Get (Row, Active_Position).Bool;
   begin
      if Stored_Key /= Physical_Key (Table, Id) then
         raise Data_Error with "stored Improve physical identity is inconsistent";
      elsif not Active then
         raise Data_Error with "inactive Improve persistence row is unsupported";
      end if;
      return
        (Id => Id, Parent_Id => Natural (Database.Rows.Get (Row, Parent_Id_Position).Int),
         Kind => Database.Rows.Get (Row, Kind_Position).Text,
         State => Database.Rows.Get (Row, State_Position).Text,
         Payload => Database.Rows.Get (Row, Payload_Position).Text, Active => Active,
         Table_Id => Table);
   exception
      when Constraint_Error =>
         raise Data_Error with "stored Improve physical identity is malformed";
   end From_Row;

   function Key_Of (Item : Entity) return Positive is (Physical_Key (Item.Table_Id, Item.Id));

   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));

   function New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;

      procedure Add
        (Position    : Natural;
         Column_Name : Wide_Wide_String;
         Kind        : Database.Types.Value_Kind;
         Primary_Key : Boolean := False) is
      begin
         if Database.Schema.Column_Count (Result) /= Position then
            raise Program_Error with "Improve schema column positions are inconsistent";
         end if;
         Database.Schema.Add_Column (Result, Column_Name, Kind, False, Primary_Key);
         if Database.Schema.Column_Count (Result) /= Position + 1 or else
           Result.Columns.Element (Position).Id /= Position
         then
            raise Program_Error with "database assigned an unexpected Improve column identity";
         end if;
      end Add;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String (Name);
      Add (Physical_Key_Position, "physical_id", Database.Types.Integer_Value, Primary_Key => True);
      Add (Table_Id_Position, "table_id", Database.Types.Integer_Value);
      Add (Id_Position, "id", Database.Types.Integer_Value);
      Add (Parent_Id_Position, "parent_id", Database.Types.Integer_Value);
      Add (Kind_Position, "kind", Database.Types.Text_Value);
      Add (State_Position, "state", Database.Types.Text_Value);
      Add (Payload_Position, "payload", Database.Types.Text_Value);
      Add (Active_Position, "active", Database.Types.Boolean_Value);
      return Result;
   end New_Schema;
end Improve.Persistence_Schema;
