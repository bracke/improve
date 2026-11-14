--  Read joined inspection history from one database snapshot.
separate (Improve.Storage)
function History
  (Item    : in out Store;
   Plan_Id : String;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Inspection_History is
   Tx              : Database.Transactions.Transaction;
   Result          : Inspection_History;
   Parent          : constant Positive := Plan_Row_Id (Plan_Id);
   Publication_Count  : Natural := 0;
   Verification_Count : Natural := 0;
   use type Improve.Model.Verification_Scope;

   procedure Count_Row (Count : in out Natural; Context : String) is
   begin
      if Count >= Limits.Maximum_History then
         raise Data_Error with Context & " history exceeds configured item limit";
      end if;
      Count := Count + 1;
   end Count_Row;

   procedure Append_Publication (Row : Entity; Already_Counted : Boolean := False) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Publication_Data;
   begin
      if not Already_Counted then Count_Row (Publication_Count, "publication"); end if;
      Require_Payload_Limit (Payload, Limits, "publication mapping payload");
      Data := Improve.Persistence_Records.Decode_Publication (Payload);
      Improve.Persistence_Validation.Validate (Data, Plan_Id);
      if Result.Publications.Length >= Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "publication query exceeds configured item limit";
      end if;
      Result.Publications.Append
        (Publication_Record'
           (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
            Harness_Task_Id => Data.Harness_Id,
            Origin          => Data.Origin,
            Contract        => Data.Contract,
            State           => To_Unbounded_String (S (Row.State)),
            Plan_Revision   => Data.Plan_Revision));
   end Append_Publication;

   procedure Append_Verification (Row : Entity; Already_Counted : Boolean := False) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Verification_Data;
   begin
      if not Already_Counted then Count_Row (Verification_Count, "verification"); end if;
      Require_Payload_Limit (Payload, Limits, "verification evidence payload");
      Data := Improve.Persistence_Records.Decode_Verification (Payload);
      Improve.Persistence_Validation.Validate
        (Data, Plan_Id, Expected_Record_Key => S (Row.Kind));
      declare
         Scope : constant Improve.Model.Verification_Scope := Data.Scope;
         Stored_Task : constant String :=
           (if Scope = Improve.Model.Task_Evaluation and then Length (Data.Task_Id) > 0
            then To_String (Data.Task_Id)
            elsif Scope = Improve.Model.Task_Evaluation then S (Row.Kind)
            else "");
      begin
         if Result.Verifications.Length >= Ada.Containers.Count_Type (Maximum) then
            raise Data_Error with "verification query exceeds configured item limit";
         end if;
         Result.Verifications.Append
           (Verification_Record'
              (Scope                => Scope,
               Task_Id              => To_Unbounded_String (Stored_Task),
               Plan_Revision        => Data.Plan_Revision,
               Contract_Fingerprint => Data.Contract,
               Assessment_Id        => Data.Assessment_Id,
               Outcome              => Parse_Outcome (S (Row.State)),
               Comparable           => Data.Comparable,
               Explanation          => Data.Explanation));
      end;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored verification evidence is malformed";
   end Append_Verification;

   procedure Read_Current (Table : Positive) is
      Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Table, Parent);
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         if Table = Publications_Table then
            Append_Publication (Entity_Tables.Element (Cursor));
         else
            Append_Verification (Entity_Tables.Element (Cursor));
         end if;
         Advance_Children (Item, Tx, Table, Parent, Cursor);
      end loop;
   end Read_Current;

   procedure Read_Legacy (Table : Positive) is
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Table);
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
            Matches : Boolean := False;
         begin
            if Table = Publications_Table then
               Count_Row (Publication_Count, "publication");
               Require_Payload_Limit (Payload, Limits, "publication mapping payload");
               Matches := Row.Parent_Id = 0 and then
                 To_String (Improve.Persistence_Records.Decode_Publication (Payload).Plan_Id) = Plan_Id;
               if Matches then Append_Publication (Row, Already_Counted => True); end if;
            else
               Count_Row (Verification_Count, "verification");
               Require_Payload_Limit (Payload, Limits, "verification evidence payload");
               Matches := Row.Parent_Id = 0 and then
                 To_String (Improve.Persistence_Records.Decode_Verification (Payload).Plan_Id) = Plan_Id;
               if Matches then Append_Verification (Row, Already_Counted => True); end if;
            end if;
         end;
         Advance (Item, Tx, Table, Cursor);
      end loop;
   end Read_Legacy;

   procedure Validate_Contracts is
      Contracts             : String_Value_Maps.Map;
      Publication_Identities : String_Value_Maps.Map;
      Verification_Identities : String_Value_Maps.Map;
   begin
      for Mapping of Result.Publications loop
         declare
            Key : constant String :=
              Contract_Key (Plan_Id, Mapping.Plan_Revision, To_String (Mapping.Improve_Task_Id));
            Identity : constant String :=
              To_String (Mapping.Improve_Task_Id) & Character'Val (0) & To_String (Mapping.Contract);
         begin
            Cache_Contracts (Item, Plan_Id, Mapping.Plan_Revision, Limits, Contracts);
            if not Contracts.Contains (Key) then
               raise Data_Error with "publication references an unknown persisted task";
            elsif Mapping.Contract /= Contracts.Element (Key) then
               raise Data_Error with "publication does not match the persisted task contract";
            elsif Publication_Identities.Contains (Identity) then
               raise Data_Error with "duplicate persisted publication mapping";
            end if;
            Publication_Identities.Insert (Identity, Mapping.Harness_Task_Id);
         end;
      end loop;
      for Evidence of Result.Verifications loop
         declare
            Record_Key : constant String :=
              (if Evidence.Scope = Improve.Model.Task_Evaluation
               then To_String (Evidence.Task_Id)
               else "@plan");
            Key : constant String := Contract_Key (Plan_Id, Evidence.Plan_Revision, Record_Key);
            Identity : constant String :=
              Number (Evidence.Plan_Revision) & Character'Val (0) &
              Improve.Model.Image (Evidence.Scope) & Character'Val (0) &
              To_String (Evidence.Task_Id) & Character'Val (0) &
              Number (Evidence.Assessment_Id) & Character'Val (0) &
              To_String (Evidence.Contract_Fingerprint);
         begin
            Cache_Contracts (Item, Plan_Id, Evidence.Plan_Revision, Limits, Contracts);
            if not Contracts.Contains (Key) then
               raise Data_Error with "verification references an unknown persisted task";
            elsif Evidence.Contract_Fingerprint /= Contracts.Element (Key) then
               raise Data_Error with "verification does not match the persisted evaluation contract";
            elsif Verification_Identities.Contains (Identity) then
               raise Data_Error with "duplicate persisted verification evidence";
            end if;
            Verification_Identities.Insert (Identity, Evidence.Explanation);
         end;
      end loop;
   end Validate_Contracts;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   Read_Current (Publications_Table);
   Read_Current (Verifications_Table);
   if Item.Schema_Version < 3 then
      Read_Legacy (Publications_Table);
      Read_Legacy (Verifications_Table);
   end if;
   Database.Transactions.Rollback (Tx);
   Validate_Contracts;
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end History;
