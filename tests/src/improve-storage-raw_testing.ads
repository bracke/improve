--  Test-only access to lifecycle-invalid persistence rows.
private package Improve.Storage.Raw_Testing is
   procedure Deactivate_Row (Path : String; Table, Id : Positive);
   --  Mark one persisted row inactive without weakening production reads.
end Improve.Storage.Raw_Testing;
