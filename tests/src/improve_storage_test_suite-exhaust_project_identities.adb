separate (Improve_Storage_Test_Suite)
procedure Exhaust_Project_Identities (Path : String) is
   DB     : Database.Handle;
   Tx     : Database.Transactions.Transaction;
   Schema : constant Database.Schema.Table_Schema := Raw_Schema;
   Row    : constant Raw_Entity :=
     (Id        => 100_000_000,
      Parent_Id => 0,
      Kind      => To_Unbounded_Wide_Wide_String ("exhausted-project-identity"),
      State     => To_Unbounded_Wide_Wide_String ("active"),
      Payload   => To_Unbounded_Wide_Wide_String ("fixture=true"),
      Active    => True,
      Table_Id  => 2);
begin
   Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
   Assert (Database.Last_Operation_Succeeded (DB), "state database could not be reopened for identity fixture");
   Database.Transactions.Begin_Write (DB, Tx);
   Assert
     (Raw_Tables.Insert (Tx, DB, Schema, Row).Code = Database.Status.Ok,
      "identity exhaustion fixture could not be inserted");
   Database.Transactions.Commit (Tx);
   Database.Close (DB);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      if Database.Is_Open (DB) then Database.Close (DB); end if;
      raise;
end Exhaust_Project_Identities;
