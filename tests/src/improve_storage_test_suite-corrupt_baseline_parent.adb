separate (Improve_Storage_Test_Suite)
procedure Corrupt_Baseline_Parent
  (Path : String; Baseline_Id : Positive) is
   DB     : Database.Handle;
   Tx     : Database.Transactions.Transaction;
   Schema : constant Database.Schema.Table_Schema := Raw_Schema;
   Row    : Raw_Entity;
   Status : Database.Status.Result;
begin
   Database.Open (DB, Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Path));
   Assert (Database.Last_Operation_Succeeded (DB), "state database could not be opened for baseline corruption");
   Database.Transactions.Begin_Write (DB, Tx);
   Status := Raw_Tables.Find (Tx, DB, Schema, Physical_Key (3, Baseline_Id), Row);
   Assert (Status.Code = Database.Status.Ok, "baseline fixture is missing");
   Row.Parent_Id := 99_999_999;
   Assert
     (Raw_Tables.Update (Tx, DB, Schema, Row).Code = Database.Status.Ok,
      "baseline fixture could not be corrupted");
   Database.Transactions.Commit (Tx);
   Database.Close (DB);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      if Database.Is_Open (DB) then Database.Close (DB); end if;
      raise;
end Corrupt_Baseline_Parent;
