with Ada.Strings.Wide_Wide_Unbounded;
with Database.Predicates;
with Database.Status;
with Database.Values;
with Improve.Storage_Codec;

package body Improve.Storage.Allocation is
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage_Codec;

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Data_Error with Context & ": " & Decode (To_Wide_Wide_String (Status.Message));
      end if;
   end Check;

   function Scan
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive) return Persistence_Entity_Tables.Cursor is
      Cursor : Persistence_Entity_Tables.Cursor;
   begin
      Check
        (Persistence_Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table),
            Database.Predicates.Column_Equals
              (1, Database.Values.From_Integer (Integer (Table))), Cursor),
         "scan identity namespace");
      return Cursor;
   end Scan;

   procedure Advance
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      Cursor : in out Persistence_Entity_Tables.Cursor) is
   begin
      Check
        (Persistence_Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table),
            Database.Predicates.Column_Equals
              (1, Database.Values.From_Integer (Integer (Table))), Cursor),
         "advance identity namespace");
   end Advance;

   procedure Begin_Transaction (Item : in out Store) is
   begin
      Item.Next_Ids := [others => 0];
      Item.Dirty_Ids := [others => False];
   end Begin_Transaction;

   function Reserve
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      Count : Positive) return Positive is
      Counter  : Persistence_Entity;
      Status   : Database.Status.Result;
      First    : Positive;
   begin
      if Table = Schema_Metadata_Table then
         raise Data_Error with "schema metadata identities are not dynamically allocated";
      end if;
      if Item.Next_Ids (Table) = 0 then
         if Item.Schema_Version < 7 then
            declare
               Cursor  : Persistence_Entity_Tables.Cursor := Scan (Item, Tx, Table);
               Highest : Natural := 0;
            begin
               while Persistence_Entity_Tables.Has_Element (Cursor) loop
                  Highest := Natural'Max (Highest, Persistence_Entity_Tables.Element (Cursor).Id);
                  Advance (Item, Tx, Table, Cursor);
               end loop;
               Item.Next_Ids (Table) := Highest + 1;
            end;
         else
            Status := Persistence_Entity_Tables.Find
              (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
               Persistence_Physical_Key (Schema_Metadata_Table, Table), Counter);
            Check (Status, "read logical identity counter");
            if S (Counter.Kind) /= "id_counter" or else
              Positive'Value (Field (S (Counter.Payload), "logical_table")) /= Table
            then
               raise Data_Error with "logical identity counter is inconsistent";
            end if;
            Item.Next_Ids (Table) := Positive'Value (S (Counter.State));
         end if;
      end if;
      First := Positive (Item.Next_Ids (Table));
      if First > Maximum_Logical_Id or else Count - 1 > Maximum_Logical_Id - First
      then
         raise Data_Error with "Improve logical identity space is exhausted";
      end if;
      Item.Next_Ids (Table) := First + Count;
      if Item.Schema_Version >= 7 then
         Item.Dirty_Ids (Table) := True;
      end if;
      return First;
   exception
      when Constraint_Error =>
         raise Data_Error with "logical identity counter is malformed";
   end Reserve;

   function Next
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive) return Positive is
     (Reserve (Item, Tx, Table, 1));

   procedure Flush
     (Item : in out Store;
      Tx   : in out Database.Transactions.Transaction) is
   begin
      if Item.Schema_Version < 7 then
         return;
      end if;
      for Table in 2 .. Logical_Table_Count loop
         if Item.Dirty_Ids (Table) then
            declare
               Counter : Persistence_Entity;
               Status  : Database.Status.Result;
            begin
               Status := Persistence_Entity_Tables.Find
                 (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
                  Persistence_Physical_Key (Schema_Metadata_Table, Table), Counter);
               Check (Status, "read logical identity counter for commit");
               Counter.State := WW (Number (Item.Next_Ids (Table)));
               Check
                 (Persistence_Entity_Tables.Update
                    (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Counter),
                  "commit logical identity counter");
            end;
         end if;
      end loop;
   end Flush;
end Improve.Storage.Allocation;
