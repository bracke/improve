separate (Improve.Storage)
procedure Close (Item : in out Store) is
   procedure Reset is
   begin
      Item.Opened := False;
      Item.Writable := False;
      Item.Schema_Version := 0;
      Item.Store_Id := Null_Unbounded_String;
      Item.Next_Ids := [others => 0];
      Item.Dirty_Ids := [others => False];
   end Reset;
begin
   if not Item.Opened then
      return;
   end if;
   Database.Close (Item.DB);
   if Database.Is_Open (Item.DB) then
      Check (Database.Last_Result (Item.DB), "close Improve state");
      raise Data_Error with "close Improve state: database remained open";
   end if;
   declare
      Status : constant Database.Status.Result := Database.Last_Result (Item.DB);
   begin
      Reset;
      Check (Status, "close Improve state");
   end;
end Close;
