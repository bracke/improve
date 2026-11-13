separate (Improve.Storage)
function List
  (Item    : in out Store;
   Project : Improve.Model.Project_Reference;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Read_Limits := Default_Read_Limits) return Summary_Vectors.Vector is
   Result : Summary_Vectors.Vector;
   Tx : Database.Transactions.Transaction;
   Plans : Entity_Tables.Cursor;
   Current_Key : constant String := Project_Key (Project);
   Legacy_Key  : constant String := Legacy_Project_Key (Project);
   Scanned     : Natural := 0;

   procedure Read (Key : String) is
   begin
      Plans := Scan_Kind (Item, Tx, Plans_Table, Key);
      while Entity_Tables.Has_Element (Plans) loop
         if Scanned >= Limits.Maximum_History then
            raise Data_Error with "plan query exceeds configured history limit";
         end if;
         Scanned := Scanned + 1;
         declare
            Row    : constant Entity := Entity_Tables.Element (Plans);
            Latest : constant Natural :=
              Latest_Revision_Id (Item, Tx, Row.Id, Limits.Maximum_History, Scanned);
         begin
            if Latest > 0 then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "plan query exceeds configured item limit";
               end if;
               declare
                  Revision : Entity;
                  Status   : constant Database.Status.Result :=
                    Entity_Tables.Find
                      (Tx, Item.DB, Item.Schemas (Revisions_Table),
                       Physical_Key (Revisions_Table, Positive (Latest)), Revision);
               begin
                  Check (Status, "read plan identity summary");
                  declare
                     Payload    : constant String := S (Revision.Payload);
                     Provenance : constant Stored_Provenance :=
                       Provenance_Of (Item, Tx, Revision, Payload, Limits);
                  begin
                     if Provenance.Project.Id = Project.Id and then
                       Provenance.Project.Path = Project.Path and then
                       Provenance.Project.Database_Id = Project.Database_Id
                     then
                        Result.Append (Summary_Of (Item, Tx, Positive (Latest), Limits));
                     end if;
                  end;
               end;
            end if;
         end;
         Advance_Kind (Item, Tx, Plans_Table, Key, Plans);
      end loop;
   end Read;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   Read (Current_Key);
   if Legacy_Key /= Current_Key then Read (Legacy_Key); end if;
   Database.Transactions.Rollback (Tx);
   return Result;
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end List;
