with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Database;
with Database.Rows;
with Database.Schema;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Values;
with Improve.Persistence_Schema;

package body Improve.Storage.Raw_Testing is
   use Improve.Persistence_Schema;

   function Identity (Row : Database.Rows.Row) return Database.Rows.Row is (Row);
   function Key_Of (Row : Database.Rows.Row) return Positive is
     (Positive (Database.Rows.Get (Row, Physical_Key_Position).Int));
   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));

   package Raw_Entity_Tables is new Database.Tables.Typed
     (Database.Rows.Row, Positive, Identity, Identity, Key_Of, Key_Value);

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Program_Error with Context;
      end if;
   end Check;

   procedure Deactivate_Row (Path : String; Table, Id : Positive) is
      DB     : Database.Handle;
      Tx     : Database.Transactions.Transaction;
      Schema : constant Database.Schema.Table_Schema := New_Schema ("improve_records");
      Row    : Database.Rows.Row;
   begin
      Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
      if not Database.Last_Operation_Succeeded (DB) then
         raise Program_Error with "state database could not be opened for test corruption";
      end if;
      Database.Transactions.Begin_Write (DB, Tx);
      Check
        (Database.Transactions.Result (Tx),
         "inactive fixture transaction could not be started");
      Check
        (Raw_Entity_Tables.Find (Tx, DB, Schema, Physical_Key (Table, Id), Row),
         "inactive fixture row is missing");
      Database.Rows.Replace (Row, Active_Position, Database.Values.From_Boolean (False));
      Check
        (Raw_Entity_Tables.Update (Tx, DB, Schema, Row),
         "fixture row could not be deactivated");
      Check
        (Database.Transactions.Commit (Tx),
         "inactive fixture row could not be committed");
      Database.Close (DB);
      Check (Database.Last_Result (DB), "state database could not be closed after test corruption");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Check
              (Database.Transactions.Rollback (Tx),
               "inactive fixture transaction could not be rolled back");
         end if;
         if Database.Is_Open (DB) then
            Database.Close (DB);
            Check (Database.Last_Result (DB), "state database could not be closed after fixture failure");
         end if;
         raise;
   end Deactivate_Row;
end Improve.Storage.Raw_Testing;
