separate (Improve.Storage)
function Begin_Publication
  (Item     : in out Store;
   Plan      : Improve.Model.Plan_Revision;
   Task_Kind : String;
   Task_Ids  : Improve.Model.UString_Vectors.Vector;
   Limits   : Persistence_Limits := Default_Persistence_Limits) return Positive is
   Stored  : Improve.Model.Plan_Revision;
   Tx      : Database.Transactions.Transaction;
   Payload : Unbounded_String;
   Key     : Unbounded_String;
   Row_Id  : Positive;
   Known   : String_Id_Maps.Map;
   Seen    : String_Id_Maps.Map;
   Packed_Size : Natural := 0;
   Budget : History_Budget := New_History_Budget (Limits);
   Existing_Row : Natural := 0;
   Content_Fingerprint : Unbounded_String;
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication journaling";
   elsif Task_Ids.Is_Empty then
      raise Argument_Error with "publication operation has no tasks";
   elsif Task_Kind = "" then
      raise Argument_Error with "publication operation has no resolved task kind";
   elsif Task_Ids.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
      raise Data_Error with "publication operation exceeds configured task limit";
   end if;
   Stored := Load_Exact
     (Item, To_String (Plan.Plan_Id), Plan.Revision, Limits, Budget);
   if Stored.Fingerprint /= Plan.Fingerprint then
      raise Data_Error with "publication plan revision fingerprint does not match durable state";
   elsif Improve.Model.Plan_Content_Fingerprint (Stored) /=
     Improve.Model.Plan_Content_Fingerprint (Plan)
   then
      raise Data_Error with "publication plan content does not match durable state";
   end if;
   Content_Fingerprint := To_Unbounded_String (Improve.Model.Plan_Content_Fingerprint (Stored));
   for Index in 1 .. Natural (Stored.Tasks.Length) loop
      Known.Include (To_String (Stored.Tasks (Index).Id), Index);
   end loop;
   for Index in 1 .. Natural (Task_Ids.Length) loop
      declare
         Identity : constant String := To_String (Task_Ids (Index));
         Size     : constant Natural := Number (Identity'Length)'Length + 1 + Identity'Length;
      begin
         if not Known.Contains (Identity) then
            raise Data_Error with "publication operation references an unknown task";
         elsif Seen.Contains (Identity) then
            raise Data_Error with "publication operation contains a duplicate task";
         elsif Size > Limits.Maximum_Text_Bytes - Packed_Size then
            raise Data_Error with "publication operation exceeds configured payload limit";
         end if;
         Seen.Insert (Identity, Index);
         Packed_Size := Packed_Size + Size;
      end;
   end loop;
   Payload := To_Unbounded_String
     (Improve.Persistence_Records.Encode_Publication_Operation
        ((Plan_Id     => Plan.Plan_Id,
          Revision    => Plan.Revision,
          Fingerprint => Plan.Fingerprint,
          Content_Fingerprint => Content_Fingerprint,
          Task_Kind   => To_Unbounded_String (Task_Kind),
          Task_Ids    => Task_Ids)));
   Require_Payload_Limit
     (To_String (Payload), Limits, "publication operation payload");
   Key := To_Unbounded_String
     (Improve.Persistence_Validation.Operation_Key
        ((Plan_Id     => Plan.Plan_Id,
          Revision    => Plan.Revision,
          Fingerprint => Plan.Fingerprint,
          Content_Fingerprint => Content_Fingerprint,
          Task_Kind   => To_Unbounded_String (Task_Kind),
          Task_Ids    => Task_Ids)));
   Begin_Write_Transaction (Item.DB, Tx);
   Improve.Storage.Allocation.Begin_Transaction (Item);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, To_String (Key)); begin
      while Entity_Tables.Has_Element (Cursor) loop
         Consume_History (Budget, "publication operation history");
         declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
            if S (Row.Kind) = To_String (Key) and then S (Row.State) = "started" then
               Require_Payload_Limit
                 (S (Row.Payload), Limits, "publication operation payload");
               declare
                  Data : constant Improve.Persistence_Records.Publication_Operation_Data :=
                    Improve.Persistence_Records.Decode_Publication_Operation
                      (S (Row.Payload), Limits.Maximum_Tasks, Limits.Maximum_Text_Bytes);
               begin
                  Improve.Persistence_Validation.Validate
                    (Data, To_String (Plan.Plan_Id), Plan.Revision, To_String (Plan.Fingerprint));
                  if Improve.Persistence_Validation.Operation_Key (Data) /= S (Row.Kind) or else
                    S (Row.Payload) /= To_String (Payload)
                  then
                     raise Data_Error with "publication operation identity conflicts with durable state";
                  end if;
               end;
               if Existing_Row > 0 then
                  raise Data_Error with "duplicate pending publication operation";
               end if;
               Existing_Row := Row.Id;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, To_String (Key), Cursor);
      end loop;
   end;
   if Existing_Row > 0 then
      Rollback_Transaction (Tx, "finish existing publication lookup");
      return Positive (Existing_Row);
   end if;
   Consume_History (Budget, "publication operation history");
   Row_Id := Improve.Storage.Allocation.Next (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, 0, WW (To_String (Key)), WW ("started"),
          WW (To_String (Payload)), True, Operations_Table)),
      "journal publication start");
   Improve.Storage.Allocation.Flush (Item, Tx);
   Commit_Transaction (Tx, "commit publication start");
   return Row_Id;
end Begin_Publication;
