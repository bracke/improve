--  Read joined inspection history from one database snapshot.
separate (Improve.Storage)
function History
  (Item    : in out Store;
   Plan_Id : String;
   Revision : Natural := 0;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Persistence_Limits := Default_Persistence_Limits;
   Selection : History_Selection := Complete_History) return Inspection_History is
   Tx              : Database.Transactions.Transaction;
   Result                : Inspection_History;
   Decoded_Publications  : History_Support.Publication_Envelope_Lists.List;
   Decoded_Verifications : History_Support.Verification_Envelope_Lists.List;
   Parent                : constant Positive := Plan_Row_Id (Plan_Id);
   Budget                : History_Budget := New_History_Budget (Limits);
   procedure Select_Revision is
      Cursor   : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Parent);
      Selected : Natural := 0;
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "plan revision history");
         declare
            Payload : constant String := S (Entity_Tables.Element (Cursor).Payload);
            Value   : Positive;
         begin
            Require_Payload_Limit (Payload, Limits, "plan revision payload");
            Value := Positive'Value (Field (Payload, "revision"));
            if (Revision = 0 and then Value > Selected) or else Value = Revision then
               Selected := Value;
            end if;
         end;
         Advance_Children (Item, Tx, Revisions_Table, Parent, Cursor);
      end loop;
      if Selected = 0 or else (Revision > 0 and then Selected /= Revision) then
         raise Argument_Error with "unknown plan revision " & Plan_Id;
      end if;
      Result.Selected_Revision := Positive (Selected);
   exception
      when Constraint_Error =>
         raise Data_Error with "stored plan revision index is malformed";
   end Select_Revision;

   procedure Count_Row (Context : String) is
   begin
      Consume_History (Budget, Context & " history");
   end Count_Row;

   procedure Append_Publication (Row : Entity; Already_Counted : Boolean := False) is
      Envelope : History_Support.Publication_Envelope;
   begin
      if not Already_Counted then Count_Row ("publication"); end if;
      History_Support.Decode_Publication
        (Item, Row, Expected_Plan_Id => Plan_Id, Limits => Limits,
         Value => Envelope);
      if Decoded_Publications.Length >= Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "publication query exceeds configured item limit";
      end if;
      Decoded_Publications.Append (Envelope);
   end Append_Publication;

   procedure Append_Verification (Row : Entity; Already_Counted : Boolean := False) is
      Envelope : History_Support.Verification_Envelope;
   begin
      if not Already_Counted then Count_Row ("verification"); end if;
      History_Support.Decode_Verification
        (Item, Row, Expected_Plan_Id => Plan_Id, Limits => Limits,
         Value => Envelope);
      if Decoded_Verifications.Length >= Ada.Containers.Count_Type (Maximum) then
         raise Data_Error with "verification query exceeds configured item limit";
      end if;
      Decoded_Verifications.Append (Envelope);
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
               Count_Row ("publication");
               Require_Payload_Limit (Payload, Limits, "publication mapping payload");
               Matches := Row.Parent_Id = 0 and then
                 To_String (Improve.Persistence_Records.Decode_Publication (Payload).Plan_Id) = Plan_Id;
               if Matches then Append_Publication (Row, Already_Counted => True); end if;
            else
               Count_Row ("verification");
               Require_Payload_Limit (Payload, Limits, "verification evidence payload");
               Matches := Row.Parent_Id = 0 and then
                 To_String (Improve.Persistence_Records.Decode_Verification (Payload).Plan_Id) = Plan_Id;
               if Matches then Append_Verification (Row, Already_Counted => True); end if;
            end if;
         end;
         Advance (Item, Tx, Table, Cursor);
      end loop;
   end Read_Legacy;

begin
   Begin_Read_Transaction (Item.DB, Tx);
   Select_Revision;
   if Selection /= Verification_History then
      Read_Current (Publications_Table);
   end if;
   if Selection /= Publication_History then
      Read_Current (Verifications_Table);
   end if;
   if Item.Schema_Version < 3 then
      if Selection /= Verification_History then
         Read_Legacy (Publications_Table);
      end if;
      if Selection /= Publication_History then
         Read_Legacy (Verifications_Table);
      end if;
   end if;
   Rollback_Transaction (Tx, "finish history query");
   History_Support.Validate_Publications
     (Item, Decoded_Publications, Limits, Budget);
   History_Support.Validate_Verifications
     (Item, Decoded_Verifications, Limits, Budget);
   while not Decoded_Publications.Is_Empty loop
      Result.Publications.Append (Decoded_Publications.First_Element.Value);
      Decoded_Publications.Delete_First;
   end loop;
   while not Decoded_Verifications.Is_Empty loop
      Result.Verifications.Append (Decoded_Verifications.First_Element.Value);
      Decoded_Verifications.Delete_First;
   end loop;
   return Result;
end History;
