separate (Improve.Storage)
overriding procedure Finalize (Item : in out Store) is
begin
   Close (Item);
exception
   when others => null;
end Finalize;
