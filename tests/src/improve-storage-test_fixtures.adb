with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;

package body Improve.Storage.Test_Fixtures is
   use type Database.Status_Code;

   procedure Require_Open (Item : Session; Context : String) is
   begin
      if not Database.Last_Operation_Succeeded (Item.DB) then
         raise Program_Error with Context;
      end if;
   end Require_Open;

   overriding procedure Finalize (Item : in out Session) is
   begin
      Close (Item);
   exception
      when others =>
         null;
   end Finalize;

   function Raw_Schema return Database.Schema.Table_Schema is
     (Persistence_New_Schema ("improve_records"));

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if Status.Code /= Database.Status.Ok then
         raise Program_Error with Context;
      end if;
   end Check;

   procedure Create (Item : in out Session; Path : String) is
   begin
      Database.Create
        (Item.DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Require_Open (Item, "foreign database fixture could not be created");
   end Create;

   procedure Open_Read_Only (Item : in out Session; Path : String) is
   begin
      Database.Open_Read_Only
        (Item.DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Require_Open (Item, "foreign database fixture could not be inspected");
   end Open_Read_Only;

   procedure Open_Read (Item : in out Session; Path : String) is
   begin
      Database.Open
        (Item.DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Require_Open (Item, "state database could not be opened for test inspection");
      Database.Transactions.Begin_Read (Item.DB, Item.Tx);
      Check
        (Database.Transactions.Result (Item.Tx),
         "test fixture read transaction could not be started");
   end Open_Read;

   procedure Open_Write (Item : in out Session; Path : String) is
   begin
      Database.Open
        (Item.DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      Require_Open (Item, "state database could not be opened for test corruption");
      Database.Transactions.Begin_Write (Item.DB, Item.Tx);
      Check
        (Database.Transactions.Result (Item.Tx),
         "test fixture write transaction could not be started");
   end Open_Write;

   procedure Close (Item : in out Session) is
   begin
      begin
         if Database.Transactions.Is_Active (Item.Tx) then
            Check
              (Database.Transactions.Rollback (Item.Tx),
               "test fixture transaction could not be rolled back");
         end if;
      exception
         when others =>
            begin
               if Database.Is_Open (Item.DB) then
                  Database.Close (Item.DB);
               end if;
            exception
               when others =>
                  null;
            end;
            raise;
      end;
      if Database.Is_Open (Item.DB) then
         Database.Close (Item.DB);
         Check (Database.Last_Result (Item.DB), "test fixture database could not be closed");
      end if;
   end Close;

   procedure Commit (Item : in out Session) is
   begin
      Check
        (Database.Transactions.Commit (Item.Tx),
         "test fixture transaction could not be committed");
      Database.Close (Item.DB);
      Check (Database.Last_Result (Item.DB), "test fixture database could not be closed");
   end Commit;
end Improve.Storage.Test_Fixtures;
