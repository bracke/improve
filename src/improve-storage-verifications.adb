separate (Improve.Storage)
function Verifications
  (Item    : in out Store;
   Plan_Id : String := "";
   Task_Id : String := "";
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Verification_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Verification_Vectors.Vector;
   History_Count : Natural := 0;

   procedure Count_Row is
   begin
      if History_Count >= Limits.Maximum_History then
         raise Data_Error with "verification history exceeds configured item limit";
      end if;
      History_Count := History_Count + 1;
   end Count_Row;

   procedure Append_Row
     (Row              : Entity;
      Expected_Plan_Id : String;
      Already_Counted  : Boolean := False) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Verification_Data;
   begin
      if not Already_Counted then Count_Row; end if;
      Require_Payload_Limit (Payload, Limits, "verification evidence payload");
      Data := Improve.Persistence_Records.Decode_Verification (Payload);
      Improve.Persistence_Validation.Validate
        (Data, Expected_Plan_Id, Expected_Record_Key => S (Row.Kind));
      declare
         Scope : constant Verification_Scope :=
           (case Data.Scope is
               when Improve.Persistence_Records.Task_Scope    => Task_Evaluation,
               when Improve.Persistence_Records.Plan_Scope    => Plan_Evaluation,
               when Improve.Persistence_Records.Project_Scope => Project_Evaluation);
         Stored_Task : constant String :=
           (if Scope = Task_Evaluation and then Length (Data.Task_Id) > 0
            then To_String (Data.Task_Id)
            elsif Scope = Task_Evaluation then S (Row.Kind)
            else "");
      begin
         if Task_Id = "" or else (Scope = Task_Evaluation and then Stored_Task = Task_Id) then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "verification query exceeds configured item limit";
            end if;
            Result.Append
              (Verification_Record'
                 (Scope         => Scope,
                  Task_Id       => To_Unbounded_String (Stored_Task),
                  Plan_Revision => Data.Plan_Revision,
                  Contract_Fingerprint => Data.Contract,
                  Assessment_Id => Data.Assessment_Id,
                  Outcome       => Parse_Outcome (S (Row.State)),
                  Comparable    => Data.Comparable,
                  Explanation   => Data.Explanation));
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
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Parent_Id = 0 then
                  raise Data_Error with "verification evidence has no owning plan";
               end if;
               Append_Row (Row, Id_Image ("PLAN-", Positive (Row.Parent_Id)));
            end;
            Advance (Item, Tx, Verifications_Table, Cursor);
         end loop;
      end;
   else
      declare
         Parent : constant Positive := Plan_Row_Id (Plan_Id);
         Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Parent);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor), Plan_Id);
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
                  Count_Row;
                  Require_Payload_Limit (Payload, Limits, "verification evidence payload");
                  if Row.Parent_Id = 0 and then
                    To_String (Improve.Persistence_Records.Decode_Verification (Payload).Plan_Id) = Plan_Id
                  then
                     Append_Row (Row, Plan_Id, Already_Counted => True);
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
