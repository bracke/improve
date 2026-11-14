separate (Improve.Storage)
procedure Cache_Contracts
  (Item      : in out Store;
   Plan_Id   : String;
   Revision  : Positive;
   Limits    : Read_Limits;
   Contracts : in out String_Value_Maps.Map) is
   Marker : constant String := Contract_Key (Plan_Id, Revision, "@plan");
begin
   if Contracts.Contains (Marker) then
      return;
   end if;
   declare
      Plan     : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
      Bindings : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
        Improve.Model.Effective_Task_Contracts (Plan);
   begin
      Contracts.Insert (Marker, Plan.Fingerprint);
      for Binding of Bindings loop
         Contracts.Insert
           (Contract_Key (Plan_Id, Revision, To_String (Binding.Task_Id)), Binding.Fingerprint);
      end loop;
   end;
exception
   when Argument_Error =>
      raise Data_Error with "persisted history references an unknown plan revision";
end Cache_Contracts;
