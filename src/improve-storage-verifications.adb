--  Read verification evidence from one consistent history snapshot.
separate (Improve.Storage)
function Verifications
  (Item    : in out Store;
   Plan_Id : String := "";
   Task_Id : String := "";
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Persistence_Limits := Default_Persistence_Limits) return Verification_Vectors.Vector is
   Result  : Verification_Vectors.Vector;
   Decoded : History_Support.Verification_Envelope_Lists.List;
   Tx      : Database.Transactions.Transaction;
   Budget  : History_Budget := New_History_Budget (Limits);
   use type Improve.Model.Verification_Scope;
begin
   if Plan_Id /= "" then
      declare Snapshot : constant Inspection_History :=
        History
          (Item, Plan_Id, Maximum => Limits.Maximum_History, Limits => Limits,
           Selection => Verification_History);
      begin
         for Evidence of Snapshot.Verifications loop
            if Task_Id = "" or else
              (Evidence.Scope = Improve.Model.Task_Evaluation and then
               To_String (Evidence.Task_Id) = Task_Id)
            then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "verification query exceeds configured item limit";
               end if;
               Result.Append (Evidence);
            end if;
         end loop;
         return Result;
      end;
   end if;
   Begin_Read_Transaction (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table); begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "verification query history");
         declare
            Row      : constant Entity := Entity_Tables.Element (Cursor);
            Envelope : History_Support.Verification_Envelope;
         begin
            History_Support.Decode_Verification
              (Item, Row, Expected_Plan_Id => "", Limits => Limits,
               Value => Envelope);
            Decoded.Append (Envelope);
         end;
         Advance (Item, Tx, Verifications_Table, Cursor);
      end loop;
   end;
   Rollback_Transaction (Tx, "finish verification query");
   History_Support.Validate_Verifications (Item, Decoded, Limits, Budget);
   while not Decoded.Is_Empty loop
      if Task_Id = "" or else
        (Decoded.First_Element.Value.Scope = Improve.Model.Task_Evaluation and then
         To_String (Decoded.First_Element.Value.Task_Id) = Task_Id)
      then
         if Result.Length >= Ada.Containers.Count_Type (Maximum) then
            raise Data_Error with "verification query exceeds configured item limit";
         end if;
         Result.Append (Decoded.First_Element.Value);
      end if;
      Decoded.Delete_First;
   end loop;
   return Result;
exception
   when Constraint_Error =>
      raise Data_Error with "stored verification evidence is malformed";
end Verifications;
