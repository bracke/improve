separate (Improve.Storage)
function Begin_Publication
  (Item     : in out Store;
   Plan      : Improve.Model.Plan_Revision;
   Task_Kind : String;
   Task_Ids  : Improve.Model.UString_Vectors.Vector;
   Limits   : Read_Limits := Default_Read_Limits) return Positive is
   Stored  : constant Improve.Model.Plan_Revision :=
     Load (Item, To_String (Plan.Plan_Id), Plan.Revision, Limits);
   Tx      : Database.Transactions.Transaction;
   Packed  : Unbounded_String;
   Key     : Unbounded_String;
   Row_Id  : Positive;
   Known   : String_Id_Maps.Map;
   Seen    : String_Id_Maps.Map;
   Packed_Size : Natural := 0;
begin
   if not Item.Opened or else not Item.Writable then
      raise Data_Error with "Improve state is not open for publication journaling";
   elsif Task_Ids.Is_Empty then
      raise Argument_Error with "publication operation has no tasks";
   elsif Task_Kind = "" then
      raise Argument_Error with "publication operation has no resolved task kind";
   elsif Task_Ids.Length > Ada.Containers.Count_Type (Limits.Maximum_Tasks) then
      raise Data_Error with "publication operation exceeds configured task limit";
   elsif Stored.Fingerprint /= Plan.Fingerprint then
      raise Data_Error with "publication plan revision fingerprint does not match durable state";
   end if;
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
   Packed := To_Unbounded_String (Pack (Task_Ids));
   Key := To_Unbounded_String
     ("publish:" & To_String (Plan.Plan_Id) & ":" & Number (Plan.Revision) & ":" &
      Stable_Digest (Task_Kind & Character'Val (0) & To_String (Packed)));
   Database.Transactions.Begin_Write (Item.DB, Tx);
   declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, To_String (Key)); begin
      while Entity_Tables.Has_Element (Cursor) loop
         declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
            if S (Row.Kind) = To_String (Key) and then S (Row.State) = "started" then
               Database.Transactions.Rollback (Tx);
               return Row.Id;
            end if;
         end;
         Advance_Kind (Item, Tx, Operations_Table, To_String (Key), Cursor);
      end loop;
   end;
   Row_Id := Next_Id (Item, Tx, Operations_Table);
   Check
     (Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Operations_Table),
         (Row_Id, 0, WW (To_String (Key)), WW ("started"),
          WW (Pair ("plan_id", To_String (Plan.Plan_Id)) & LF &
              Pair ("revision", Number (Plan.Revision)) & LF &
              Pair ("fingerprint", To_String (Plan.Fingerprint)) & LF &
              Pair ("task_kind", Task_Kind) & LF &
              Pair ("task_ids", To_String (Packed))), True, Operations_Table)),
      "journal publication start");
   Database.Transactions.Commit (Tx);
   return Row_Id;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Begin_Publication;
