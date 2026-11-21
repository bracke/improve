--  Test-only access to private CLI integrity seams.
package Improve.CLI.Testing is
   function Rejects_Between_Pass_Change
     (Path, Replacement : String;
      Maximum_Bytes     : Positive) return Boolean;
   --  Replace a file after its first read and report whether the bounded reader rejects it.
end Improve.CLI.Testing;
