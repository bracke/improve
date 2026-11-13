separate (Improve.Storage)
procedure Record_Verification
  (Item    : in out Store;
   Plan_Id : String;
   Values  : Verification_Vectors.Vector) is
   Tx     : Database.Transactions.Transaction;
   Row_Id : Positive;
   Stored : String_Value_Maps.Map;
   Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

   function Scope_Image (Value : Verification_Scope) return String is
     (case Value is
         when Task_Evaluation => "task",
         when Plan_Evaluation => "plan",
         when Project_Evaluation => "project");

   function Record_Key (Value : Verification_Record) return String is
     (case Value.Scope is
         when Task_Evaluation => To_String (Value.Task_Id),
         when Plan_Evaluation => "@plan",
         when Project_Evaluation => "@project");

   function Identity_Key
     (Key, Plan, Assessment, Revision, Contract : String) return String is
     (Key & Character'Val (0) & Plan & Character'Val (0) & Assessment & Character'Val (0) &
      Revision & Character'Val (0) & Contract);

   function Stored_Value (State, Scope, Comparable, Explanation : String) return String is
     (State & Character'Val (0) & Scope & Character'Val (0) & Comparable & Character'Val (0) & Explanation);
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for verification recording";
   end if;
   for Value of Values loop
      if Value.Scope = Task_Evaluation and then Length (Value.Task_Id) = 0 then
         raise Data_Error with "task verification has no task identity";
      elsif Value.Scope /= Task_Evaluation and then Length (Value.Task_Id) > 0 then
         raise Data_Error with "aggregate verification must not name a task";
      end if;
      declare
         Plan : constant Improve.Model.Plan_Revision :=
           Load (Item, Plan_Id, Value.Plan_Revision);
         Expected : constant String :=
           (if Value.Scope = Task_Evaluation then
               Improve.Model.Effective_Task_Contract_Fingerprint (Plan, Value.Task_Id)
            else To_String (Plan.Fingerprint));
      begin
         if To_String (Value.Contract_Fingerprint) /= Expected then
            raise Data_Error with "verification does not match the persisted evaluation contract";
         end if;
      end;
   end loop;
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Plan_Row); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            declare Key : constant String := Identity_Key
                 (S (Row.Kind), Field (Payload, "plan_id"), Field (Payload, "assessment_id"),
                  Field_Or (Payload, "plan_revision", "1"), Field_Or (Payload, "contract", ""));
            begin
               if Stored.Contains (Key) then
                  raise Data_Error with "duplicate persisted verification evidence";
               end if;
               Stored.Insert
              (Key,
               To_Unbounded_String
                 (Stored_Value
                    (S (Row.State), Field_Or (Payload, "scope", "task"),
                     Field (Payload, "comparable"), Field (Payload, "explanation"))));
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
           (Improve.Model.Image (Value.Outcome), Scope_Image (Value.Scope), Boolean_Image (Value.Comparable),
            To_String (Value.Explanation));
         Existing : constant Boolean := Stored.Contains (Identity);
      begin
         if Existing and then To_String (Stored.Element (Identity)) /= Expected then
            raise Data_Error with "verification evidence conflicts for task and assessment";
         end if;
         if not Existing then
            Row_Id := Next_Id (Item, Tx, Verifications_Table);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Verifications_Table),
                  (Row_Id, Plan_Row, WW (Key), WW (Improve.Model.Image (Value.Outcome)),
                   WW (Pair ("plan_id", Plan_Id) & LF &
                       Pair ("assessment_id", Number (Value.Assessment_Id)) & LF &
                       Pair ("plan_revision", Number (Value.Plan_Revision)) & LF &
                       Pair ("contract", To_String (Value.Contract_Fingerprint)) & LF &
                       Pair ("scope", Scope_Image (Value.Scope)) & LF &
                       Pair ("task_id", To_String (Value.Task_Id)) & LF &
                       Pair ("comparable", Boolean_Image (Value.Comparable)) & LF &
                       Pair ("explanation", To_String (Value.Explanation))), True, Verifications_Table)),
               "record verification evidence");
            Stored.Insert (Identity, To_Unbounded_String (Expected));
         end if;
      end;
   end loop;
   Database.Transactions.Commit (Tx);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Record_Verification;
