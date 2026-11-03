--  Deterministic remediation planning over immutable Ada Quality evidence.
package Improve with SPARK_Mode is
   Version : constant String := "0.1.0";
   --  Application version.

   JSON_Format_Version : constant := 1;
   --  Version of every machine-readable output envelope.

   Argument_Error   : exception;
   --  Invalid command, option, configuration, or selection; exit code 2.

   Dependency_Error : exception;
   --  Required evidence or project state is unavailable; exit code 3.

   Data_Error       : exception;
   --  Storage, integrity, publication, or internal processing failure; exit code 4.

   function Stable_Digest (Text : String) return String;
   --  Return a deterministic FNV-1a identity in the form `fnv1a64:` plus sixteen lowercase hexadecimal digits.
   --  @param Text Bytes to identify.
   --  @return Stable digest.
end Improve;

