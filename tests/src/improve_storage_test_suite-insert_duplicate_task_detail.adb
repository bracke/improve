separate (Improve_Storage_Test_Suite)
procedure Insert_Duplicate_Task_Detail
  (Path : String; Task_Row : Positive) is
   DB     : Database.Handle;
   Tx     : Database.Transactions.Transaction;
   Schema : constant Database.Schema.Table_Schema := Raw_Schema;
   Row    : constant Raw_Entity :=
     (Id        => 99_000_000,
      Parent_Id => Task_Row,
      Kind      => To_Unbounded_Wide_Wide_String ("goal"),
      State     => To_Unbounded_Wide_Wide_String ("value"),
      Payload   => To_Unbounded_Wide_Wide_String ("conflicting persisted goal"),
      Active    => True,
      Table_Id  => 13);
begin
   Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
   Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for detail corruption");
   Database.Transactions.Begin_Write (DB, Tx);
   Assert
     (Raw_Tables.Insert (Tx, DB, Schema, Row).Code = Database.Status.Ok,
      "duplicate task-detail fixture could not be inserted");
   Database.Transactions.Commit (Tx);
   Database.Close (DB);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      if Database.Is_Open (DB) then Database.Close (DB); end if;
      raise;
end Insert_Duplicate_Task_Detail;
