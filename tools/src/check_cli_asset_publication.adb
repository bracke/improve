with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Hostkit.Fs;
with Hostkit.Locks;
with Improve_CLI_Asset_Publication;
with Project_Tools.Files;
with Project_Tools.Test_Fixtures;

--  Fault-injection check for generated CLI asset publication rollback.
procedure Check_CLI_Asset_Publication is
   use Ada.Strings.Unbounded;
   use type Hostkit.Locks.Lock_Outcome;

   Replace_Calls : Natural := 0;
   Fail_Restore  : Boolean := False;
   Fail_Commit   : Boolean := True;
   Fail_Write    : Boolean := False;
   Fail_Copy     : Boolean := False;
   Fail_Delete   : Boolean := False;

   Root : constant String := Project_Tools.Test_Fixtures.Fresh_Temp_Dir ("improve-cli-assets");
   Lock_Path : constant String := Project_Tools.Files.Join (Root, "publication.lock");

   function Failing_Replace (Source, Target : String) return Boolean is
   begin
      Replace_Calls := Replace_Calls + 1;
      if (Fail_Commit and then Replace_Calls = 2) or else (Fail_Restore and then Replace_Calls = 3) then
         return False;
      end if;
      return Hostkit.Fs.Replace_File (Source, Target);
   end Failing_Replace;

   procedure Failing_Write (Path, Content : String) is
   begin
      if Fail_Write then
         raise Program_Error with "injected write failure";
      end if;
      Project_Tools.Files.Write_Raw_File (Path, Content);
   end Failing_Write;

   procedure Failing_Copy (Source, Target : String) is
   begin
      if Fail_Copy then
         raise Program_Error with "injected copy failure";
      end if;
      Ada.Directories.Copy_File (Source, Target);
   end Failing_Copy;

   procedure Failing_Delete (Path : String) is
   begin
      if Fail_Delete then
         raise Program_Error with "injected delete failure";
      end if;
      Ada.Directories.Delete_File (Path);
   end Failing_Delete;

   package Asset_Publication is new Improve_CLI_Asset_Publication
     (Lock_Path    => Lock_Path,
      Replace_File => Failing_Replace,
      Write_File   => Failing_Write,
      Copy_File    => Failing_Copy,
      Delete_File  => Failing_Delete);

   Paths : constant Asset_Publication.Asset_Array :=
     [To_Unbounded_String (Project_Tools.Files.Join (Root, "bash")),
      To_Unbounded_String (Project_Tools.Files.Join (Root, "zsh")),
      To_Unbounded_String (Project_Tools.Files.Join (Root, "fish")),
      To_Unbounded_String (Project_Tools.Files.Join (Root, "manpage"))];
   Old_Contents : constant Asset_Publication.Asset_Array :=
     [To_Unbounded_String ("old-bash"), To_Unbounded_String ("old-zsh"),
      To_Unbounded_String ("old-fish"), To_Unbounded_String ("old-manpage")];
   New_Contents : constant Asset_Publication.Asset_Array :=
     [To_Unbounded_String ("new-bash"), To_Unbounded_String ("new-zsh"),
      To_Unbounded_String ("new-fish"), To_Unbounded_String ("new-manpage")];
   Stage_Suffix    : constant String := ".improve.tmp";
   Backup_Suffix   : constant String := ".improve.bak";
   Failed          : Boolean := False;
   Failure_Message : Unbounded_String;

   procedure Write_Old_Contents is
   begin
      for Index in Paths'Range loop
         Project_Tools.Files.Write_Raw_File (To_String (Paths (Index)), To_String (Old_Contents (Index)));
      end loop;
   end Write_Old_Contents;

   procedure Reset_Fixture is
   begin
      Fail_Delete := False;
      Fail_Commit := False;
      Fail_Restore := False;
      for Path of Paths loop
         declare
            Target : constant String := To_String (Path);
            Stage  : constant String := Target & Stage_Suffix;
            Backup : constant String := Target & Backup_Suffix;
         begin
            if Ada.Directories.Exists (Stage) then
               Ada.Directories.Delete_File (Stage);
            end if;
            if Ada.Directories.Exists (Backup) then
               Ada.Directories.Delete_File (Backup);
            end if;
         end;
      end loop;
      Write_Old_Contents;
   end Reset_Fixture;

   procedure Assert_Old_And_Clean (Context : String) is
   begin
      for Index in Paths'Range loop
         declare
            Path : constant String := To_String (Paths (Index));
         begin
            if Project_Tools.Files.Read_Raw_File (Path) /= To_String (Old_Contents (Index)) then
               raise Program_Error with Context & " changed " & Path;
            elsif Ada.Directories.Exists (Path & Stage_Suffix) or else
              Ada.Directories.Exists (Path & Backup_Suffix)
            then
               raise Program_Error with Context & " left an artifact for " & Path;
            end if;
         end;
      end loop;
   end Assert_Old_And_Clean;
begin
   Write_Old_Contents;
   begin
      Asset_Publication.Publish (Paths, New_Contents);
   exception
      when Error : Program_Error =>
         Failed := True;
         Failure_Message := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
   end;
   if not Failed or else Replace_Calls /= 3 then
      raise Program_Error with "CLI asset publication fault was not exercised as expected";
   end if;
   for Index in Paths'Range loop
      declare
         Path : constant String := To_String (Paths (Index));
      begin
         if Project_Tools.Files.Read_Raw_File (Path) /= To_String (Old_Contents (Index)) then
            raise Program_Error with "CLI asset rollback did not preserve " & Path;
         end if;
         if Ada.Directories.Exists (Path & Stage_Suffix) or else
           Ada.Directories.Exists (Path & Backup_Suffix)
         then
            raise Program_Error with "CLI asset rollback left transaction artifacts for " & Path;
         end if;
      end;
   end loop;
   Assert_Old_And_Clean ("failed replacement rollback");
   Replace_Calls := 0;
   Fail_Restore := True;
   Failed := False;
   Failure_Message := Null_Unbounded_String;
   Write_Old_Contents;
   begin
      Asset_Publication.Publish (Paths, New_Contents);
   exception
      when Error : Program_Error =>
         Failed := True;
         Failure_Message := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
   end;
   if not Failed or else Replace_Calls /= 3 then
      raise Program_Error with "CLI asset publication restore fault was not exercised as expected";
   elsif Project_Tools.Files.Read_Raw_File (To_String (Paths (Paths'First))) /=
     To_String (New_Contents (New_Contents'First))
   then
      raise Program_Error with "failed rollback unexpectedly changed the committed target";
   elsif Project_Tools.Files.Read_Raw_File
       (To_String (Paths (Paths'First)) & Backup_Suffix) /=
     To_String (Old_Contents (Old_Contents'First))
   then
      raise Program_Error with "failed rollback did not preserve its recovery backup";
   elsif Ada.Strings.Fixed.Index
       (To_String (Failure_Message), To_String (Paths (Paths'First)) & Backup_Suffix) = 0
   then
      raise Program_Error with "failed rollback did not report its recovery backup";
   end if;
   for Index in Paths'Range loop
      declare
         Path : constant String := To_String (Paths (Index));
      begin
         if Ada.Directories.Exists (Path & Stage_Suffix) then
            raise Program_Error with "failed rollback retained a staging file for " & Path;
         elsif Index > Paths'First and then
           Project_Tools.Files.Read_Raw_File (Path) /= To_String (Old_Contents (Index))
         then
            raise Program_Error with "failed rollback modified an uncommitted target " & Path;
         elsif Index > Paths'First and then Ada.Directories.Exists (Path & Backup_Suffix) then
            raise Program_Error with "failed rollback retained an unnecessary backup for " & Path;
         end if;
      end;
   end loop;
   Reset_Fixture;

   declare
      Held    : Hostkit.Locks.Lock;
      Outcome : constant Hostkit.Locks.Lock_Outcome :=
        Hostkit.Locks.Acquire (Lock_Path, Hostkit.Locks.Lock_Exclusive, Wait => False, Item => Held);
   begin
      if Outcome /= Hostkit.Locks.Lock_Ok then
         raise Program_Error with "could not acquire publication lock for concurrency test";
      end if;
      Fail_Commit := False;
      Replace_Calls := 0;
      Failed := False;
      begin
         Asset_Publication.Publish (Paths, New_Contents);
      exception
         when Error : Program_Error =>
            Failed := True;
            Failure_Message := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
      end;
      Hostkit.Locks.Release (Held);
      if not Failed or else Ada.Strings.Fixed.Index (To_String (Failure_Message), "already in progress") = 0 then
         raise Program_Error with "concurrent CLI asset publication was not rejected";
      end if;
   exception
      when others =>
         if Hostkit.Locks.Is_Held (Held) then
            Hostkit.Locks.Release (Held);
         end if;
         raise;
   end;
   Assert_Old_And_Clean ("concurrent publication rejection");

   for Failure in 1 .. 2 loop
      Reset_Fixture;
      Replace_Calls := 0;
      Failed := False;
      Fail_Write := Failure = 1;
      Fail_Copy := Failure = 2;
      begin
         Asset_Publication.Publish (Paths, New_Contents);
      exception
         when Program_Error => Failed := True;
      end;
      Fail_Write := False;
      Fail_Copy := False;
      if not Failed then
         raise Program_Error with (if Failure = 1 then "write failure was not propagated" else
                                     "copy failure was not propagated");
      end if;
      Assert_Old_And_Clean (if Failure = 1 then "write failure" else "copy failure");
   end loop;

   Reset_Fixture;
   Fail_Delete := True;
   Failed := False;
   Project_Tools.Files.Write_Raw_File
     (To_String (Paths (Paths'First)) & Stage_Suffix, "stale");
   begin
      Asset_Publication.Publish (Paths, New_Contents);
   exception
      when Program_Error => Failed := True;
   end;
   Fail_Delete := False;
   if not Failed then
      raise Program_Error with "stale artifact delete failure was not propagated";
   end if;
   Reset_Fixture;

   Fail_Delete := True;
   Failed := False;
   Failure_Message := Null_Unbounded_String;
   begin
      Asset_Publication.Publish (Paths, New_Contents);
   exception
      when Error : Program_Error =>
         Failed := True;
         Failure_Message := To_Unbounded_String (Ada.Exceptions.Exception_Message (Error));
   end;
   Fail_Delete := False;
   if not Failed or else
     Ada.Strings.Fixed.Index (To_String (Failure_Message), "assets were published") = 0
   then
      raise Program_Error with "post-publication cleanup failure was not reported";
   end if;
   for Index in Paths'Range loop
      if Project_Tools.Files.Read_Raw_File (To_String (Paths (Index))) /= To_String (New_Contents (Index)) then
         raise Program_Error with "post-publication cleanup failure rolled back a committed asset";
      end if;
   end loop;
   Reset_Fixture;
   Project_Tools.Test_Fixtures.Cleanup (Root);
exception
   when others =>
      Project_Tools.Test_Fixtures.Cleanup (Root);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise;
end Check_CLI_Asset_Publication;
