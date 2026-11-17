with Ada.Finalization;
with Database;
with Database.Schema;
with Database.Status;
with Database.Transactions;

--  Exception-safe database sessions shared by storage corruption fixtures.
private package Improve.Storage.Test_Fixtures is
   type Session is new Ada.Finalization.Limited_Controlled with record
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
   end record;

   overriding procedure Finalize (Item : in out Session);

   function Raw_Schema return Database.Schema.Table_Schema;
   procedure Check (Status : Database.Status.Result; Context : String);
   procedure Create (Item : in out Session; Path : String);
   procedure Open_Read_Only (Item : in out Session; Path : String);
   procedure Open_Read (Item : in out Session; Path : String);
   procedure Open_Write (Item : in out Session; Path : String);
   procedure Close (Item : in out Session);
   procedure Commit (Item : in out Session);
end Improve.Storage.Test_Fixtures;
