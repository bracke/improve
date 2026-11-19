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

   Cancelled_Error  : exception;
   --  Cooperative user interruption; exit code 130 at the CLI boundary.

   function Stable_Digest (Text : String) return String;
   --  Return a collision-resistant identity in the form `sha256:` plus sixty-four lowercase hexadecimal digits.
   --  @param Text Bytes to identify.
   --  @return Stable digest.
end Improve;

