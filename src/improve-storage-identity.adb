separate (Improve.Storage)
function Identity (Item : Store) return String is
begin
   if not Item.Opened then
      raise Data_Error with "Improve state is not open";
   end if;
   return To_String (Item.Store_Id);
end Identity;
