with Improve.Config;

--  Terminal styling policy kept separate from command data.
package Improve.Presentation is
   procedure Configure (Format : Improve.Config.Output_Format; Color : Improve.Config.Color_Mode);
   --  Apply output styling policy; JSON always disables ANSI formatting.

   function Header (Text : String) return String;
   --  Decorate a terminal heading according to the current policy.
end Improve.Presentation;

