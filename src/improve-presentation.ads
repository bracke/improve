with Improve.Config;

--  Terminal styling policy kept separate from command data.
package Improve.Presentation is
   --  Shared terminal styling boundary for human-readable output.

   procedure Configure (Format : Improve.Config.Output_Format; Color : Improve.Config.Color_Mode);
   --  Apply output styling policy; JSON always disables ANSI formatting.
   --  @param Format Selected output format.
   --  @param Color Requested terminal color policy.

   function Header (Text : String) return String;
   --  Decorate a terminal heading according to the current policy.
   --  @param Text Heading text.
   --  @return Styled or plain heading.

   function Safe_Text (Text : String) return String;
   --  Replace terminal control characters in untrusted text with spaces.
   --  @param Text Untrusted diagnostic, path, title, or evidence text.
   --  @return Single-line terminal-safe text.
end Improve.Presentation;

