with Ada.Directories;
with Hostkit.Locks;

package body Improve_CLI_Asset_Publication is
   use Ada.Strings.Unbounded;
   use type Hostkit.Locks.Lock_Outcome;

   type Boolean_Array is array (Positive range <>) of Boolean;

   procedure Publish (Paths, Contents : Asset_Array) is
      Stage_Suffix  : constant String := ".improve.tmp";
      Backup_Suffix : constant String := ".improve.bak";
      Backed_Up     : Boolean_Array (Paths'Range) := [others => False];
      Committed     : Boolean_Array (Paths'Range) := [others => False];
      Restored      : Boolean_Array (Paths'Range) := [others => False];
      Publication_Committed : Boolean := False;
      Publication_Lock      : Hostkit.Locks.Lock;

      function Stage_Path (Path : String) return String is (Path & Stage_Suffix);
      function Backup_Path (Path : String) return String is (Path & Backup_Suffix);

      function Discard (Path : String) return Boolean is
      begin
         if Ada.Directories.Exists (Path) then
            Delete_File (Path);
         end if;
         return True;
      exception
         when others => return False;
      end Discard;

      procedure Record_Failure (Failures : in out Unbounded_String; Path : String) is
      begin
         if Length (Failures) > 0 then
            Append (Failures, ", ");
         end if;
         Append (Failures, Path);
      end Record_Failure;

      procedure Require_Discard (Path : String) is
      begin
         if not Discard (Path) then
            raise Program_Error with "could not remove stale CLI asset transaction artifact " & Path;
         end if;
      end Require_Discard;

      procedure Discard_Stages (Failures : in out Unbounded_String) is
      begin
         for Path of Paths loop
            declare
               Artifact : constant String := Stage_Path (To_String (Path));
            begin
               if not Discard (Artifact) then
                  Record_Failure (Failures, Artifact);
               end if;
            end;
         end loop;
      end Discard_Stages;

      procedure Discard_Backups (Failures : in out Unbounded_String) is
      begin
         for Path of Paths loop
            declare
               Artifact : constant String := Backup_Path (To_String (Path));
            begin
               if not Discard (Artifact) then
                  Record_Failure (Failures, Artifact);
               end if;
            end;
         end loop;
      end Discard_Backups;

      procedure Recover_Backups is
         Failures : Unbounded_String;
      begin
         for Index in reverse Paths'Range loop
            declare
               Path   : constant String := To_String (Paths (Index));
               Backup : constant String := Backup_Path (Path);
            begin
               if Ada.Directories.Exists (Backup) then
                  begin
                     if not Replace_File (Backup, Path) then
                        Record_Failure (Failures, Backup);
                     end if;
                  exception
                     when others => Record_Failure (Failures, Backup);
                  end;
               end if;
            end;
         end loop;
         if Length (Failures) > 0 then
            raise Program_Error with
              "could not recover interrupted CLI asset publication from: " & To_String (Failures);
         end if;
      end Recover_Backups;
   begin
      declare
         Outcome : constant Hostkit.Locks.Lock_Outcome :=
           Hostkit.Locks.Acquire
             (Lock_Path, Hostkit.Locks.Lock_Exclusive, Wait => False, Item => Publication_Lock);
      begin
         if Outcome = Hostkit.Locks.Lock_Busy then
            raise Program_Error with "CLI asset publication is already in progress";
         elsif Outcome = Hostkit.Locks.Lock_Unsupported then
            raise Program_Error with "CLI asset publication locking is unsupported for " & Lock_Path;
         elsif Outcome /= Hostkit.Locks.Lock_Ok then
            raise Program_Error with "could not lock CLI asset publication at " & Lock_Path;
         end if;
      end;
      Recover_Backups;
      for Index in Paths'Range loop
         declare
            Path : constant String := To_String (Paths (Index));
         begin
            Require_Discard (Stage_Path (Path));
            Write_File (Stage_Path (Path), To_String (Contents (Index)));
         end;
      end loop;
      for Index in Paths'Range loop
         declare
            Path : constant String := To_String (Paths (Index));
         begin
            Copy_File (Path, Backup_Path (Path));
            Backed_Up (Index) := True;
         end;
      end loop;
      for Index in Paths'Range loop
         declare
            Path : constant String := To_String (Paths (Index));
         begin
            if not Replace_File (Stage_Path (Path), Path) then
               raise Program_Error with "could not atomically replace " & Path;
            end if;
            Committed (Index) := True;
         end;
      end loop;
      Publication_Committed := True;
      declare
         Cleanup_Failures : Unbounded_String;
      begin
         Discard_Stages (Cleanup_Failures);
         Discard_Backups (Cleanup_Failures);
         if Length (Cleanup_Failures) > 0 then
            raise Program_Error with
              "CLI assets were published, but transaction artifacts could not be removed: " &
              To_String (Cleanup_Failures);
         end if;
      end;
      Hostkit.Locks.Release (Publication_Lock);
   exception
      when others =>
         if Publication_Committed then
            if Hostkit.Locks.Is_Held (Publication_Lock) then
               Hostkit.Locks.Release (Publication_Lock);
            end if;
            raise;
         end if;
         declare
            Recovery_Backups : Unbounded_String;
            Cleanup_Failures : Unbounded_String;
         begin
            for Index in reverse Paths'Range loop
               if Backed_Up (Index) and then Committed (Index) then
                  declare
                     Path   : constant String := To_String (Paths (Index));
                     Backup : constant String := Backup_Path (Path);
                  begin
                     begin
                        Restored (Index) := Replace_File (Backup, Path);
                     exception
                        when others => Restored (Index) := False;
                     end;
                     if not Restored (Index) then
                        Record_Failure (Recovery_Backups, Backup);
                     end if;
                  end;
               end if;
            end loop;
            Discard_Stages (Cleanup_Failures);
            for Index in Paths'Range loop
               if not Committed (Index) or else Restored (Index) then
                  declare
                     Artifact : constant String := Backup_Path (To_String (Paths (Index)));
                  begin
                     if not Discard (Artifact) then
                        Record_Failure (Cleanup_Failures, Artifact);
                     end if;
                  end;
               end if;
            end loop;
            if Length (Recovery_Backups) > 0 or else Length (Cleanup_Failures) > 0 then
               if Hostkit.Locks.Is_Held (Publication_Lock) then
                  Hostkit.Locks.Release (Publication_Lock);
               end if;
               raise Program_Error with
                 "CLI asset publication failed" &
                 (if Length (Recovery_Backups) = 0 then ""
                  else "; rollback was incomplete; recovery backup preserved at: " &
                    To_String (Recovery_Backups)) &
                 (if Length (Cleanup_Failures) = 0 then ""
                  else "; transaction artifacts could not be removed: " & To_String (Cleanup_Failures));
            end if;
         end;
         if Hostkit.Locks.Is_Held (Publication_Lock) then
            Hostkit.Locks.Release (Publication_Lock);
         end if;
         raise;
   end Publish;
end Improve_CLI_Asset_Publication;
