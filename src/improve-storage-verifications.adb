separate (Improve.Storage)
function Verifications
  (Item    : in out Store;
   Plan_Id : String := "";
   Task_Id : String := "";
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Verification_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Verification_Vectors.Vector;

   procedure Append_Row (Row : Entity) is
      Payload : constant String := S (Row.Payload);
   begin
      Require_Payload_Limit (Payload, Limits, "verification evidence payload");
      declare
         Scope : constant Verification_Scope := Parse_Scope (Field_Or (Payload, "scope", "task"));
         Stored_Task : constant String :=
           (if Scope = Task_Evaluation then Field_Or (Payload, "task_id", S (Row.Kind)) else "");
      begin
         if Task_Id = "" or else (Scope = Task_Evaluation and then Stored_Task = Task_Id) then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "verification query exceeds configured item limit";
            end if;
            Result.Append
              (Verification_Record'
                 (Scope         => Scope,
                  Task_Id       => To_Unbounded_String (Stored_Task),
                  Plan_Revision => Positive'Value (Field_Or (Payload, "plan_revision", "1")),
                  Contract_Fingerprint => To_Unbounded_String (Field_Or (Payload, "contract", "")),
                  Assessment_Id => Positive'Value (Field (Payload, "assessment_id")),
                  Outcome       => Parse_Outcome (S (Row.State)),
                  Comparable    => Boolean'Value (Field (Payload, "comparable")),
                  Explanation   => To_Unbounded_String (Field (Payload, "explanation"))));
         end if;
      end;
   exception
      when Constraint_Error => raise Data_Error with "stored verification evidence is malformed";
   end Append_Row;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   if Plan_Id = "" then
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor));
            Advance (Item, Tx, Verifications_Table, Cursor);
         end loop;
      end;
   else
      declare
         Parent : constant Positive := Plan_Row_Id (Plan_Id);
         Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Parent);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor));
            Advance_Children (Item, Tx, Verifications_Table, Parent, Cursor);
         end loop;
      end;
      if Item.Schema_Version < 3 then
         declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table); begin
            while Entity_Tables.Has_Element (Cursor) loop
               declare
                  Row : constant Entity := Entity_Tables.Element (Cursor);
                  Payload : constant String := S (Row.Payload);
               begin
                  Require_Payload_Limit (Payload, Limits, "verification evidence payload");
                  if Row.Parent_Id = 0 and then Field (Payload, "plan_id") = Plan_Id then
                     Append_Row (Row);
                  end if;
               end;
               Advance (Item, Tx, Verifications_Table, Cursor);
            end loop;
         end;
      end if;
   end if;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Verifications;
