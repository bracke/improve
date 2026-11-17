with Database.Transactions;

--  Durable logical identity allocation for Improve state namespaces.
private package Improve.Storage.Allocation is
   --  Transaction-scoped logical identity reservation for storage namespaces.

   procedure Begin_Transaction (Item : in out Store);
   --  Reset in-memory reservations before a new write transaction.
   --  @param Item Store beginning a write transaction.

   function Reserve
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      Count : Positive) return Positive;
   --  Reserve a contiguous identity range in one logical namespace.
   --  @param Item Store owning the durable namespace counters.
   --  @param Tx Active write transaction.
   --  @param Table Logical namespace receiving the reservation.
   --  @param Count Positive number of identities requested.
   --  @return First reserved logical identity.

   function Next
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive) return Positive;
   --  Reserve one logical identity.
   --  @param Item Store owning the durable namespace counters.
   --  @param Tx Active write transaction.
   --  @param Table Logical namespace receiving the identity.
   --  @return Reserved logical identity.

   procedure Flush
     (Item : in out Store;
      Tx   : in out Database.Transactions.Transaction);
   --  Write changed durable counters into the owning transaction.
   --  @param Item Store whose reservations are flushed.
   --  @param Tx Active write transaction that owns the reservations.
end Improve.Storage.Allocation;
