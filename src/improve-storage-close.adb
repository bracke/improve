separate (Improve.Storage)
procedure Close (Item : in out Store) is
begin
   if Item.Opened then Database.Close (Item.DB); end if;
   Item.Opened := False;
   Item.Writable := False;
   Item.Schema_Version := 0;
   Item.Store_Id := Null_Unbounded_String;
   Item.Next_Ids := [others => 0];
end Close;
