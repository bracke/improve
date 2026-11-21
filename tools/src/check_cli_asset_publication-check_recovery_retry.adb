separate (Check_CLI_Asset_Publication)
procedure Check_Recovery_Retry is
begin
   Fail_Restore := False;
   Fail_Commit := False;
   Replace_Calls := 0;
   Asset_Publication.Publish (Paths, New_Contents);
   for Index in Paths'Range loop
      declare
         Path : constant String := To_String (Paths (Index));
      begin
         if Project_Tools.Files.Read_Raw_File (Path) /= To_String (New_Contents (Index)) then
            raise Program_Error with "recovery retry did not publish " & Path;
         elsif Ada.Directories.Exists (Path & Stage_Suffix) or else
           Ada.Directories.Exists (Path & Backup_Suffix)
         then
            raise Program_Error with "recovery retry left an artifact for " & Path;
         end if;
      end;
   end loop;
end Check_Recovery_Retry;
