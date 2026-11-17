with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Status;

package body Improve.Storage.Lifecycle_Testing is
   function Message (Status : Database.Status.Result) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
        (Ada.Strings.Wide_Wide_Unbounded.To_Wide_Wide_String (Status.Message)));

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Program_Error with Context & ": " & Message (Status);
      end if;
   end Check;

   procedure Hold_Read
     (Item : in out Store;
      Hold : in out Read_Hold) is
   begin
      if Database.Transactions.Is_Active (Hold.Tx) then
         raise Program_Error with "test read transaction is already active";
      end if;
      Database.Transactions.Begin_Read (Item.DB, Hold.Tx);
      Check
        (Database.Transactions.Result (Hold.Tx),
         "test read transaction could not be started");
   end Hold_Read;

   procedure Release (Hold : in out Read_Hold) is
   begin
      if Database.Transactions.Is_Active (Hold.Tx) then
         Check
           (Database.Transactions.Rollback (Hold.Tx),
            "test read transaction could not be released");
      end if;
   end Release;

   overriding procedure Finalize (Hold : in out Read_Hold) is
   begin
      if Database.Transactions.Is_Active (Hold.Tx) then
         declare
            Status : constant Database.Status.Result :=
              Database.Transactions.Rollback (Hold.Tx);
            pragma Unreferenced (Status);
         begin
            null;
         end;
      end if;
   exception
      when others =>
         null;
   end Finalize;
end Improve.Storage.Lifecycle_Testing;
