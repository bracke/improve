separate (Improve.Storage)
function Publications
  (Item       : in out Store;
   Plan_Id    : String := "";
   Maximum    : Positive := Default_Query_Maximum;
   Limits     : Read_Limits := Default_Read_Limits) return Publication_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Publication_Vectors.Vector;
   Owners : Improve.Model.UString_Vectors.Vector;
   History_Count : Natural := 0;

   procedure Count_Row is
   begin
      if History_Count >= Limits.Maximum_History then
         raise Data_Error with "publication history exceeds configured item limit";
      end if;
      History_Count := History_Count + 1;
   end Count_Row;

   procedure Append_Row
     (Row             : Entity;
      Expected_Plan_Id : String;
      Already_Counted : Boolean := False) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Publication_Data;
   begin
      if not Already_Counted then Count_Row; end if;
      Require_Payload_Limit (Payload, Limits, "publication mapping payload");
      Data := Improve.Persistence_Records.Decode_Publication (Payload);
      Improve.Persistence_Validation.Validate (Data, Expected_Plan_Id);
      if Result.Length >= Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "publication query exceeds configured item limit";
      end if;
      Result.Append
        (Publication_Record'
           (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
            Harness_Task_Id => Data.Harness_Id,
            Origin          => Data.Origin,
            Contract        => Data.Contract,
            State           => To_Unbounded_String (S (Row.State)),
            Plan_Revision   => Data.Plan_Revision));
      Owners.Append (To_Unbounded_String (Expected_Plan_Id));
   end Append_Row;

   procedure Validate_Contracts is
      Contracts : String_Value_Maps.Map;
      Identities : String_Value_Maps.Map;
      Index     : Natural := Owners.First_Index;
   begin
      for Mapping of Result loop
         declare
            Owner : constant String := To_String (Owners (Index));
            Key   : constant String :=
              Contract_Key
                (Owner, Mapping.Plan_Revision, To_String (Mapping.Improve_Task_Id));
            Identity : constant String :=
              Owner & Character'Val (0) & To_String (Mapping.Improve_Task_Id) &
              Character'Val (0) & To_String (Mapping.Contract);
         begin
            Cache_Contracts (Item, Owner, Mapping.Plan_Revision, Limits, Contracts);
            if not Contracts.Contains (Key) then
               raise Data_Error with "publication references an unknown persisted task";
            elsif Mapping.Contract /= Contracts.Element (Key) then
               raise Data_Error with "publication does not match the persisted task contract";
            elsif Identities.Contains (Identity) then
               raise Data_Error with "duplicate persisted publication mapping";
            end if;
            Identities.Insert (Identity, Mapping.Harness_Task_Id);
         end;
         Index := Index + 1;
      end loop;
   end Validate_Contracts;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   if Plan_Id = "" then
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Parent_Id = 0 then
                  raise Data_Error with "publication mapping has no owning plan";
               end if;
               Append_Row (Row, Id_Image ("PLAN-", Positive (Row.Parent_Id)));
            end;
            Advance (Item, Tx, Publications_Table, Cursor);
         end loop;
      end;
   else
      declare
         Parent : constant Positive := Plan_Row_Id (Plan_Id);
         Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Parent);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor), Plan_Id);
            Advance_Children (Item, Tx, Publications_Table, Parent, Cursor);
         end loop;
      end;
      if Item.Schema_Version < 3 then
         declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
            while Entity_Tables.Has_Element (Cursor) loop
               declare
                  Row : constant Entity := Entity_Tables.Element (Cursor);
                  Payload : constant String := S (Row.Payload);
               begin
                  Count_Row;
                  Require_Payload_Limit (Payload, Limits, "publication mapping payload");
                  if Row.Parent_Id = 0 and then
                    To_String (Improve.Persistence_Records.Decode_Publication (Payload).Plan_Id) = Plan_Id
                  then
                     Append_Row (Row, Plan_Id, Already_Counted => True);
                  end if;
               end;
               Advance (Item, Tx, Publications_Table, Cursor);
            end loop;
         end;
      end if;
   end if;
   Database.Transactions.Rollback (Tx);
   Validate_Contracts;
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Publications;
