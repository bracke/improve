with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Schema;
with Improve.Storage.Test_Fixtures;

package body Improve.Storage.Identity_Testing is
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage.Test_Fixtures;

   function Identity_Counter_State (Path : String) return String is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
      Result : Unbounded_Wide_Wide_String;
   begin
      Open_Read (Item, Path);
      for Table in 2 .. Logical_Table_Count loop
         Check
           (Persistence_Entity_Tables.Find
              (Item.Tx, Item.DB, Schema,
               Persistence_Physical_Key (Schema_Metadata_Table, Table), Row),
            "logical identity counter could not be read");
         Append (Result, To_Wide_Wide_String (Row.State));
         Append (Result, ";");
      end loop;
      Close (Item);
      return Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
        (To_Wide_Wide_String (Result));
   end Identity_Counter_State;

   function Task_Identity_Counter_Value (Path : String) return String is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Read (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key (Schema_Metadata_Table, Tasks_Table), Row),
         "logical identity counter could not be read");
      Close (Item);
      return Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
        (To_Wide_Wide_String (Row.State));
   end Task_Identity_Counter_Value;

   procedure Exhaust_Project_Identities (Path : String) is
      Item   : Session;
      Schema : constant Database.Schema.Table_Schema := Raw_Schema;
      Row    : Persistence_Entity;
   begin
      Open_Write (Item, Path);
      Check
        (Persistence_Entity_Tables.Find
           (Item.Tx, Item.DB, Schema,
            Persistence_Physical_Key
              (Schema_Metadata_Table, Projects_Table), Row),
         "project identity counter could not be read");
      Row.State := To_Unbounded_Wide_Wide_String ("100000001");
      Check
        (Persistence_Entity_Tables.Update (Item.Tx, Item.DB, Schema, Row),
         "project identity counter could not be exhausted");
      Commit (Item);
   end Exhaust_Project_Identities;
end Improve.Storage.Identity_Testing;
