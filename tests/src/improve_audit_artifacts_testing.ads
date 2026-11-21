--  Focused integrity and signing checks for exported audit artifacts.
package Improve_Audit_Artifacts_Testing is
   --  Exercise valid, tampered, malformed, and forward-compatible state cases.
   procedure Check;

   --  Exercise audit export, signing-option, and verification CLI contracts.
   procedure Check_CLI;
end Improve_Audit_Artifacts_Testing;
