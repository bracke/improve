package body Improve.Storage_Values is
   function Priority_Value (Text : String) return Improve.Model.Priority is
   begin
      for Value in Improve.Model.Priority loop
         if Improve.Model.Image (Value) = Text then
            return Value;
         end if;
      end loop;
      raise Data_Error with "invalid persisted priority " & Text;
   end Priority_Value;

   function Kind_Value (Text : String) return Improve.Model.Candidate_Kind is
   begin
      for Value in Improve.Model.Candidate_Kind loop
         if Improve.Model.Image (Value) = Text then
            return Value;
         end if;
      end loop;
      raise Data_Error with "invalid persisted candidate kind " & Text;
   end Kind_Value;

   function Indicator_Value (Text : String) return Ada_Quality.Types.Indicator_Id is
   begin
      for Value in Ada_Quality.Types.Indicator_Id loop
         if Ada_Quality.Types.Image (Value) = Text then
            return Value;
         end if;
      end loop;
      raise Data_Error with "invalid persisted indicator " & Text;
   end Indicator_Value;

   function Parse_Outcome (Text : String) return Improve.Model.Quality_Outcome is
   begin
      for Value in Improve.Model.Quality_Outcome loop
         if Improve.Model.Image (Value) = Text then
            return Value;
         end if;
      end loop;
      raise Data_Error with "stored verification outcome is invalid: " & Text;
   end Parse_Outcome;

   procedure Require_Payload_Limit
     (Text    : String;
      Limits  : Improve.Storage.Persistence_Limits;
      Context : String) is
   begin
      if Text'Length > Limits.Maximum_Text_Bytes then
         raise Data_Error with Context & " exceeds configured persisted-text limit";
      end if;
   end Require_Payload_Limit;
end Improve.Storage_Values;
