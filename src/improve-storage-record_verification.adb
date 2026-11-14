separate (Improve.Storage)
procedure Record_Verification
  (Item    : in out Store;
   Plan_Id : String;
   Values  : Verification_Vectors.Vector;
   Limits  : Read_Limits := Default_Read_Limits) is
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Stored : String_Value_Maps.Map;
   Contracts : String_Value_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);
   History_Count : Natural := 0;
   use type Improve.Model.Verification_Scope;

   function Record_Key (Value : Verification_Record) return String is
     (case Value.Scope is
         when Improve.Model.Task_Evaluation => To_String (Value.Task_Id),
         when Improve.Model.Plan_Evaluation => "@plan",
         when Improve.Model.Project_Evaluation => "@project");

   function Identity_Key
     (Key, Plan, Assessment, Revision, Contract : String) return String is
     (Key & Character'Val (0) & Plan & Character'Val (0) & Assessment & Character'Val (0) &
      Revision & Character'Val (0) & Contract);

   function Stored_Value (State, Scope, Comparable, Explanation : String) return String is
     (State & Character'Val (0) & Scope & Character'Val (0) & Comparable & Character'Val (0) & Explanation);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for verification recording";
   elsif Values.Length > Ada.Containers.Count_Type (Limits.Maximum_History) then
      raise Data_Error with "verification recording exceeds configured item limit";
   end if;
   for Value of Values loop
      if Value.Scope = Improve.Model.Task_Evaluation and then Length (Value.Task_Id) = 0 then
         raise Data_Error with "task verification has no task identity";
      elsif Value.Scope /= Improve.Model.Task_Evaluation and then Length (Value.Task_Id) > 0 then
         raise Data_Error with "aggregate verification must not name a task";
      end if;
      Cache_Contracts (Item, Plan_Id, Value.Plan_Revision, Limits, Contracts);
      declare
         Key : constant String := Contract_Key
           (Plan_Id, Value.Plan_Revision,
            (if Value.Scope = Improve.Model.Task_Evaluation then To_String (Value.Task_Id) else "@plan"));
      begin
         if not Contracts.Contains (Key) then
            raise Data_Error with "verification references an unknown persisted task";
         elsif Value.Contract_Fingerprint /= Contracts.Element (Key) then
            raise Data_Error with "verification does not match the persisted evaluation contract";
         end if;
      end;
   end loop;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Plan_Row); begin
      while Entity_Tables.Has_Element (Cursor) loop
         if History_Count >= Limits.Maximum_History then
            raise Data_Error with "verification history exceeds configured item limit";
         end if;
         History_Count := History_Count + 1;
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
            Data    : Improve.Persistence_Records.Verification_Data;
         begin
            Require_Payload_Limit (Payload, Limits, "verification evidence payload");
            Data := Improve.Persistence_Records.Decode_Verification (Payload);
            Improve.Persistence_Validation.Validate
              (Data, Plan_Id, Expected_Record_Key => S (Row.Kind));
            declare Key : constant String := Identity_Key
                 (S (Row.Kind), To_String (Data.Plan_Id), Number (Data.Assessment_Id),
                  Number (Data.Plan_Revision), To_String (Data.Contract));
            begin
               if Stored.Contains (Key) then
                  raise Data_Error with "duplicate persisted verification evidence";
               end if;
               Stored.Insert
              (Key,
               To_Unbounded_String
                 (Stored_Value
                    (S (Row.State), Improve.Model.Image (Data.Scope),
                     Boolean_Image (Data.Comparable),
                     To_String (Data.Explanation))));
            end;
         end;
         Advance_Children (Item, Tx, Verifications_Table, Plan_Row, Cursor);
      end loop;
   end;
   for Value of Values loop
      declare
         Key      : constant String := Record_Key (Value);
         Identity : constant String := Identity_Key
           (Key, Plan_Id, Number (Value.Assessment_Id), Number (Value.Plan_Revision),
            To_String (Value.Contract_Fingerprint));
         Expected : constant String := Stored_Value
           (Improve.Model.Image (Value.Outcome),
            Improve.Model.Image (Value.Scope), Boolean_Image (Value.Comparable),
            To_String (Value.Explanation));
         Existing : constant Boolean := Stored.Contains (Identity);
         Payload  : constant String := Improve.Persistence_Records.Encode_Verification
           ((Plan_Id       => To_Unbounded_String (Plan_Id),
             Assessment_Id => Value.Assessment_Id,
             Plan_Revision => Value.Plan_Revision,
             Contract      => Value.Contract_Fingerprint,
             Scope         => Value.Scope,
             Task_Id       => Value.Task_Id,
             Comparable    => Value.Comparable,
             Explanation   => Value.Explanation));
      begin
         if Existing and then To_String (Stored.Element (Identity)) /= Expected then
            raise Data_Error with "verification evidence conflicts for task and assessment";
         end if;
         if not Existing then
            if History_Count >= Limits.Maximum_History then
               raise Data_Error with "verification history exceeds configured item limit";
            end if;
            Require_Payload_Limit (Payload, Limits, "verification evidence payload");
            Row_Id := Next_Id (Item, Tx, Verifications_Table);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Verifications_Table),
                  (Row_Id, Plan_Row, WW (Key), WW (Improve.Model.Image (Value.Outcome)),
                   WW (Payload), True, Verifications_Table)),
               "record verification evidence");
            Stored.Insert (Identity, To_Unbounded_String (Expected));
            History_Count := History_Count + 1;
         end if;
      end;
   end loop;
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Record_Verification;
