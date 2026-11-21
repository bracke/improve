--  Deterministic generated command-line integration assets.
private package Improve.CLI_Assets is
   function Completion (Shell : String) return String;
   --  Generate completion source for one supported shell.
   --  @param Shell `bash`, `zsh`, or `fish`.
   --  @return Complete shell completion source.

   function Manpage return String;
   --  Generate the roff manual page from the supported command surface.
   --  @return Complete `improve(1)` manual page.
end Improve.CLI_Assets;
