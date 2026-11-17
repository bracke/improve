with Ada.Finalization;
with Database.Transactions;

--  Test-only controlled transaction holds for storage lifecycle failures.
package Improve.Storage.Lifecycle_Testing is
   type Read_Hold is limited private;

   procedure Hold_Read
     (Item : in out Store;
      Hold : in out Read_Hold);
   --  Hold one read transaction against an open Improve store.
   --  @param Item Open Improve store.
   --  @param Hold Controlled transaction hold to activate.

   procedure Release (Hold : in out Read_Hold);
   --  Release an active read transaction hold; an inactive hold is harmless.
   --  @param Hold Controlled transaction hold to release.

private
   type Read_Hold is new Ada.Finalization.Limited_Controlled with record
      Tx : Database.Transactions.Transaction;
   end record;

   overriding procedure Finalize (Hold : in out Read_Hold);
end Improve.Storage.Lifecycle_Testing;
