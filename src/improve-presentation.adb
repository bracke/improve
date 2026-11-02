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
     (Terminal_Styles.Decorate (Text, Terminal_Styles.Role_Header));
end Improve.Presentation;

