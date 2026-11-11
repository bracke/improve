with Terminal_Styles;

package body Improve.Presentation is
   procedure Configure (Format : Improve.Config.Output_Format; Color : Improve.Config.Color_Mode) is
      use Improve.Config;
   begin
      if Format = JSON_Format then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      else
         Terminal_Styles.Set_Color_Policy
           (case Color is
               when Color_Auto => Terminal_Styles.Color_Auto,
               when Color_Always => Terminal_Styles.Color_Always,
               when Color_Never => Terminal_Styles.Color_Never);
      end if;
   end Configure;

   function Header (Text : String) return String is
     (Terminal_Styles.Decorate (Safe_Text (Text), Terminal_Styles.Role_Header));

   function Safe_Text (Text : String) return String is
      Result : String := Text;
   begin
      for Value of Result loop
         if Character'Pos (Value) < 32 or else Character'Pos (Value) = 127 then
            Value := ' ';
         end if;
      end loop;
      return Result;
   end Safe_Text;
end Improve.Presentation;

