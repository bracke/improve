separate (Improve_Storage_Test_Suite)
procedure Insert_Unknown_Finding_Link
  (Path : String; Task_Row : Positive) is
   DB     : Database.Handle;
   Tx     : Database.Transactions.Transaction;
   Schema : constant Database.Schema.Table_Schema := Raw_Schema;
   Row    : constant Raw_Entity :=
     (Id        => 1,
      Parent_Id => Task_Row,
      Kind      => To_Unbounded_Wide_Wide_String ("unknown-finding"),
      State     => To_Unbounded_Wide_Wide_String ("linked"),
      Payload   => Null_Unbounded_Wide_Wide_String,
      Active    => True,
      Table_Id  => 8);
begin
   Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
   Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for link corruption");
   Database.Transactions.Begin_Write (DB, Tx);
   Assert
     (Raw_Tables.Insert (Tx, DB, Schema, Row).Code = Database.Status.Ok,
      "unknown finding-link fixture could not be inserted");
   Database.Transactions.Commit (Tx);
   Database.Close (DB);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      if Database.Is_Open (DB) then Database.Close (DB); end if;
      raise;
end Insert_Unknown_Finding_Link;
