separate (Improve.Storage)
procedure Consume_History
  (Budget  : in out History_Budget;
   Context : String) is
begin
   if Budget.Consumed >= Budget.Limit then
      raise Data_Error with Context & " exceeds configured item limit";
   end if;
   Budget.Consumed := Budget.Consumed + 1;
end Consume_History;
