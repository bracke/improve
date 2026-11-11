separate (Improve.Storage)
function Publications
  (Item       : in out Store;
   Plan_Id    : String := "";
   Maximum    : Positive := Default_Query_Maximum;
   Limits     : Read_Limits := Default_Read_Limits) return Publication_Vectors.Vector is
   Tx     : Database.Transactions.Transaction;
   Result : Publication_Vectors.Vector;

   procedure Append_Row (Row : Entity) is
      Payload : constant String := S (Row.Payload);
   begin
      Require_Payload_Limit (Payload, Limits, "publication mapping payload");
      if Result.Length >= Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "publication query exceeds configured item limit";
      end if;
      Result.Append
        (Publication_Record'
           (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
            Harness_Task_Id => To_Unbounded_String (Field (Payload, "harness_id")),
            Origin          => To_Unbounded_String (Field (Payload, "origin")),
            Contract        => To_Unbounded_String (Field_Or (Payload, "contract", "")),
            State           => To_Unbounded_String (S (Row.State)),
            Plan_Revision   => Positive'Value (Field_Or (Payload, "plan_revision", "1"))));
   end Append_Row;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   if Plan_Id = "" then
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor));
            Advance (Item, Tx, Publications_Table, Cursor);
         end loop;
      end;
   else
      declare
         Parent : constant Positive := Plan_Row_Id (Plan_Id);
         Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Parent);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Append_Row (Entity_Tables.Element (Cursor));
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
                  Require_Payload_Limit (Payload, Limits, "publication mapping payload");
                  if Row.Parent_Id = 0 and then Field (Payload, "plan_id") = Plan_Id then
                     Append_Row (Row);
                  end if;
               end;
               Advance (Item, Tx, Publications_Table, Cursor);
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
end Publications;
