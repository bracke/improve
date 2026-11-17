separate (Improve.Storage)
function List
  (Item    : in out Store;
   Project : Improve.Model.Project_Reference;
   Maximum : Positive := Default_Query_Maximum;
   Limits  : Persistence_Limits := Default_Persistence_Limits) return Summary_Vectors.Vector is
   Result : Summary_Vectors.Vector;
   Tx : Database.Transactions.Transaction;
   Plans : Entity_Tables.Cursor;
   Current_Key : constant String := Project_Key (Project);
   Legacy_Key  : constant String := Legacy_Project_Key (Project);
   Budget      : History_Budget := New_History_Budget (Limits);

   procedure Read (Key : String) is
   begin
      Plans := Scan_Kind (Item, Tx, Plans_Table, Key);
      while Entity_Tables.Has_Element (Plans) loop
         Consume_History (Budget, "plan query history");
         declare
            Row    : constant Entity := Entity_Tables.Element (Plans);
            Latest : constant Natural :=
              Latest_Revision_Id (Item, Tx, Row.Id, Budget);
         begin
            if Latest > 0 then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "plan query exceeds configured item limit";
               end if;
               declare
                  Summary : constant Stored_Plan_Summary :=
                    Summary_Of (Item, Tx, Positive (Latest), Limits);
               begin
                  if Summary.Project.Id = Project.Id and then
                    Summary.Project.Path = Project.Path and then
                    Summary.Project.Database_Id = Project.Database_Id
                  then
                     Result.Append (Summary.Value);
                  end if;
               end;
            end if;
         end;
         Advance_Kind (Item, Tx, Plans_Table, Key, Plans);
      end loop;
   end Read;
begin
   Begin_Read_Transaction (Item.DB, Tx);
   Read (Current_Key);
   if Result.Is_Empty and then Legacy_Key /= Current_Key then Read (Legacy_Key); end if;
   if Result.Length > 1 then
      raise Data_Error with "project has ambiguous persisted remediation plans";
   end if;
   Rollback_Transaction (Tx, "finish project plan query");
   return Result;
end List;
