separate (Improve.Storage)
function List
  (Item    : in out Store;
   Project : Improve.Model.Project_Reference;
   Maximum : Positive := Default_Query_Maximum) return Summary_Vectors.Vector is
   Result : Summary_Vectors.Vector;
   Tx : Database.Transactions.Transaction;
   Plans : Entity_Tables.Cursor;
   Current_Key : constant String := Project_Key (Project);
   Legacy_Key  : constant String := Legacy_Project_Key (Project);

   procedure Read (Key : String) is
   begin
      Plans := Scan_Kind (Item, Tx, Plans_Table, Key);
      while Entity_Tables.Has_Element (Plans) loop
         declare
            Row    : constant Entity := Entity_Tables.Element (Plans);
            Latest : constant Natural := Latest_Revision_Id (Item, Tx, Row.Id);
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
                     Payload : constant String := S (Revision.Payload);
                  begin
                     if Positive'Value (Field (Payload, "project_id")) = Project.Id and then
                       Field (Payload, "project_path") = To_String (Project.Path) and then
                       Field_Or (Payload, "quality_database", "") = To_String (Project.Database_Id)
                     then
                        Result.Append (Summary_Of (Item, Tx, Positive (Latest)));
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
