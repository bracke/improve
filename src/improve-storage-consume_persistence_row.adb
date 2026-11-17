--  Account for one persisted row while enforcing per-field and aggregate limits.
separate (Improve.Storage)
procedure Consume_Persistence_Row
  (Limits    : Persistence_Limits;
   Kind      : String;
   State     : String;
   Payload   : String;
   Context   : String;
   Total     : in out Natural;
   Operation : String) is
   procedure Consume (Text, Field : String) is
   begin
      if Text'Length > Limits.Maximum_Text_Bytes then
         raise Data_Error with Context & " " & Field & " exceeds configured persisted-text limit";
      elsif Text'Length > Limits.Maximum_Total_Bytes - Total then
         raise Data_Error with
           "plan " & Operation & " exceeds configured aggregate persisted-byte limit";
      end if;
      Total := Total + Text'Length;
   end Consume;
begin
   Consume (Kind, "identity");
   Consume (State, "state");
   Consume (Payload, "payload");
end Consume_Persistence_Row;
