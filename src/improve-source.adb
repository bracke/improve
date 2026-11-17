with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Containers.Vectors;
with Ada.Streams;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada_Quality.Types;
with CryptoLib.Hashes;
with Database.WAL;
with Hostkit.Fs;
with Improve.Canonical_Digests;
with Project_Tools.Files;

package body Improve.Source is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;
   use type Ada.Directories.File_Size;
   use type Ada_Quality.Types.Assessment_Status;
   use type Ada_Quality.Types.Indicator_Id;

   function Hex (Digest : CryptoLib.Hashes.SHA256_Digest) return String is
      Hex_Chars : constant String := "0123456789abcdef";
      Result    : String (1 .. 64);
   begin
      for Index in Digest'Range loop
         Result (2 * Index - 1) := Hex_Chars (Natural (Digest (Index)) / 16 + 1);
         Result (2 * Index) := Hex_Chars (Natural (Digest (Index)) mod 16 + 1);
      end loop;
      return Result;
   end Hex;

   function Working_Fingerprint
     (Root       : String;
      State_Path : String := "";
      Maximum_File_Bytes  : Positive := Improve.Config.Default_Maximum_Source_File_Bytes;
      Maximum_Total_Bytes : Positive := Improve.Config.Default_Maximum_Source_Total_Bytes) return String is
      package Paths is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String,
         "=" => Ada.Strings.Unbounded."=");
      package Sorting is new Paths.Generic_Sorting ("<" => Ada.Strings.Unbounded."<");
      Generated_Directories : constant Project_Tools.Files.Name_List :=
        [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
         To_Unbounded_String (".model_runner"), To_Unbounded_String ("obj"),
         To_Unbounded_String ("bin"), To_Unbounded_String ("cov-obj"),
         To_Unbounded_String ("cov-bin"), To_Unbounded_String ("coverage"),
         To_Unbounded_String ("gnatprove"), To_Unbounded_String ("tests/obj"),
         To_Unbounded_String ("tests/bin"), To_Unbounded_String ("tests/cov-obj"),
         To_Unbounded_String ("tests/cov-bin"), To_Unbounded_String ("tests/coverage"),
         To_Unbounded_String ("tests/gnatprove")];
      Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
      Canonical_State : constant Unbounded_String :=
        (if State_Path = "" then Null_Unbounded_String
         else To_Unbounded_String (Ada.Directories.Full_Name (State_Path)));
      Values : Paths.Vector;
      Context : CryptoLib.Hashes.SHA256_Context;
      Total  : Natural := 0;
      Entries_Seen : Natural := 0;
      Maximum_Depth : constant := 128;
      Maximum_Entries : constant := 100_000;

      function Skipped_Generated_Directory (Relative : String) return Boolean is
      begin
         for Value of Generated_Directories loop
            if To_String (Value) = Relative then
               return True;
            end if;
         end loop;
         return False;
      end Skipped_Generated_Directory;

      function Operational_File (Path, Relative : String) return Boolean is
         Configured : constant String := To_String (Canonical_State);
         Configured_WAL : constant String :=
           (if Configured = "" then ""
            else Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
              (Database.WAL.WAL_Path
                 (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Configured))));
      begin
         return Relative = ".improve.db" or else Relative = ".improve.db.fts" or else
           Relative = ".improve.db.wal" or else
           (Configured /= "" and then
            (Path = Configured or else Path = Configured & ".fts" or else
             Path = Configured_WAL));
      end Operational_File;

      procedure Walk
        (Directory          : String;
         Relative_Directory : String;
         Depth              : Positive) is
         Search : Ada.Directories.Search_Type;
      begin
         if Depth > Maximum_Depth then
            raise Data_Error with "project source exceeds fingerprint directory depth limit";
         end if;
         Ada.Directories.Start_Search
           (Search, Directory, "*", [Ada.Directories.Ordinary_File => True,
                                     Ada.Directories.Directory => True,
                                     Ada.Directories.Special_File => True]);
         begin
            while Ada.Directories.More_Entries (Search) loop
               declare
                  Item : Ada.Directories.Directory_Entry_Type;
               begin
                  Ada.Directories.Get_Next_Entry (Search, Item);
                  declare
                     Name : constant String := Ada.Directories.Simple_Name (Item);
                  begin
                     if Name not in "." | ".." then
                        if Entries_Seen >= Maximum_Entries then
                           raise Data_Error with "project source exceeds fingerprint entry limit";
                        end if;
                        Entries_Seen := Entries_Seen + 1;
                        declare
                           Path     : constant String := Project_Tools.Files.Join (Directory, Name);
                           Relative : constant String :=
                             (if Relative_Directory = "" then Name else Relative_Directory & "/" & Name);
                           Kind     : constant Ada.Directories.File_Kind := Ada.Directories.Kind (Item);
                        begin
                           if Hostkit.Fs.Is_Link (Path) then
                              raise Data_Error with "project source contains a symbolic link: " & Relative;
                           elsif Kind = Ada.Directories.Directory and then
                             Skipped_Generated_Directory (Relative)
                           then
                              null;
                           elsif Kind = Ada.Directories.Directory then
                              Walk (Path, Relative, Depth + 1);
                           elsif Kind = Ada.Directories.Ordinary_File and then
                             not Operational_File (Path, Relative)
                           then
                              Values.Append (To_Unbounded_String (Relative));
                           elsif Kind = Ada.Directories.Special_File then
                              raise Data_Error with "project source contains a special file: " & Relative;
                           end if;
                        end;
                     end if;
                  end;
               end;
            end loop;
            Ada.Directories.End_Search (Search);
         exception
            when others =>
               Ada.Directories.End_Search (Search);
               raise;
         end;
      end Walk;

      procedure Add (Text : String) is
         use Ada.Streams;
         Buffer : Stream_Element_Array (1 .. 65_536);
         First  : Natural := Text'First;
      begin
         while First <= Text'Last loop
            declare
               Count : constant Natural := Natural'Min (Buffer'Length, Text'Last - First + 1);
            begin
               for Offset in 0 .. Count - 1 loop
                  Buffer (Buffer'First + Stream_Element_Offset (Offset)) :=
                    Stream_Element (Character'Pos (Text (First + Offset)));
               end loop;
               CryptoLib.Hashes.Update
                 (Context, Buffer (Buffer'First .. Buffer'First + Stream_Element_Offset (Count) - 1));
               First := First + Count;
            end;
         end loop;
      end Add;

      procedure Add_Length (Value : Natural) is
      begin
         Add (Natural'Image (Value) & Character'Val (0));
      end Add_Length;

      procedure Add_File (Relative : String) is
         Text    : Unbounded_String;
         Outcome : Hostkit.Fs.Read_Beneath_Outcome;
      begin
         Hostkit.Fs.Read_Beneath (Canonical_Root, Relative, Maximum_File_Bytes, Text, Outcome);
         case Outcome is
            when Hostkit.Fs.Read_Done => null;
            when Hostkit.Fs.Read_Too_Large =>
               raise Data_Error with "project source exceeds fingerprint byte limit";
            when Hostkit.Fs.Read_Outside =>
               raise Data_Error with "project source contains an unsafe link: " & Relative;
            when others =>
               raise Data_Error with "project source changed or cannot be read: " & Relative;
         end case;
         if Length (Text) > Maximum_Total_Bytes - Total then
            raise Data_Error with "project source exceeds fingerprint byte limit";
         end if;
         Add_Length (Length (Text));
         Add (To_String (Text));
         Total := Total + Length (Text);
      end Add_File;
   begin
      Walk (Canonical_Root, "", 1);
      Sorting.Sort (Values);
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      Add ("improve-working-source-v4" & Character'Val (0));
      Add_Length (Natural (Values.Length));
      for Relative of Values loop
         declare
            Name : constant String := To_String (Relative);
         begin
            Add_Length (Name'Length);
            Add (Name);
            Add_File (Name);
         end;
      end loop;
      return "working-sha256-v4:" & Hex (CryptoLib.Hashes.Finalize (Context));
   end Working_Fingerprint;

   procedure Open
     (Item   : in out Repository;
      Path   : String;
      Limits : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Database_Bytes : Positive := Improve.Config.Default_Maximum_Quality_Database_Bytes) is
   begin
      if Item.Opened then Close (Item); end if;
      if Ada.Directories.Exists (Path) and then
        Ada.Directories.Size (Path) > Ada.Directories.File_Size (Maximum_Database_Bytes)
      then
         raise Data_Error with "quality database exceeds configured byte limit";
      end if;
      Ada_Quality.Reporting.Open (Item.Session, Path, Limits);
      Item.Opened := True;
      if Ada.Directories.Size (Path) > Ada.Directories.File_Size (Maximum_Database_Bytes) then
         Close (Item);
         raise Data_Error with "quality database exceeds configured byte limit";
      end if;
      Item.Database_Id := To_Unbounded_String (Ada.Directories.Full_Name (Path));
   exception
      when Error : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Busy_Error =>
         if Item.Opened then Close (Item); end if;
         raise Dependency_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Schema_Error | Ada_Quality.Reporting.Integrity_Error =>
         if Item.Opened then Close (Item); end if;
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Limit_Error =>
         if Item.Opened then Close (Item); end if;
         raise Data_Error with
           "quality snapshot exceeds configured limits: " & Ada.Exceptions.Exception_Message (Error);
      when others =>
         if Item.Opened then Close (Item); end if;
         raise;
   end Open;

   procedure Close (Item : in out Repository) is
   begin
      Ada_Quality.Reporting.Close (Item.Session);
      Item.Opened := False;
      Item.Database_Id := Null_Unbounded_String;
   end Close;

   overriding procedure Finalize (Item : in out Repository) is
   begin
      if Item.Opened then
         Close (Item);
      end if;
   exception
      when others => null;
   end Finalize;

   procedure Require_Open (Item : Repository) is
   begin
      if not Item.Opened then raise Data_Error with "quality repository is not open"; end if;
   end Require_Open;

   function Projects (Item : Repository) return Ada_Quality.Reporting.Project_Vectors.Vector is
   begin
      Require_Open (Item);
      return Ada_Quality.Reporting.Projects (Item.Session);
   end Projects;

   function Identity (Item : Repository) return String is
   begin
      Require_Open (Item);
      return Ada_Quality.Reporting.Snapshot_Identity (Item.Session);
   end Identity;

   function Database_Identity (Item : Repository) return String is
   begin
      Require_Open (Item);
      return To_String (Item.Database_Id);
   end Database_Identity;

   function Assessment_Fingerprint
     (Value         : Ada_Quality.Reporting.Assessment_Record;
      Maximum_Bytes : Positive := Positive'Last) return String is
      Digest : Improve.Canonical_Digests.Builder;

      procedure Add (Name, Text : String) is
      begin
         Improve.Canonical_Digests.Add (Digest, Name, Text);
      end Add;
   begin
      Improve.Canonical_Digests.Initialize
        (Digest, "improve-assessment-v1" & Character'Val (0), Maximum_Bytes);
      Add ("run", Positive'Image (Value.Run.Id));
      Add ("project", Positive'Image (Value.Run.Project_Id));
      Add ("state", Ada_Quality.Types.Assessment_Status'Image (Value.Run.State));
      Add ("source", To_String (Value.Run.Source_Id));
      Add ("policy", To_String (Value.Run.Policy_Id));
      Add ("toolchain", To_String (Value.Run.Toolchain_Id));
      Add ("result_count", Natural'Image (Natural (Value.Results.Length)));
      for Result of Value.Results loop
         Add ("indicator", Ada_Quality.Types.Image (Result.Indicator));
         Add ("execution", Ada_Quality.Types.Execution_Status'Image (Result.Execution));
         Add ("compliance", Ada_Quality.Types.Compliance_Status'Image (Result.Compliance));
         Add ("applicable", Boolean'Image (Result.Applicable));
         Add ("summary", To_String (Result.Summary));
         Add ("evidence", To_String (Result.Evidence));
         Add ("measurement", Ada_Quality.Types.Image (Result.Measurement));
         Add ("finding_count", Natural'Image (Natural (Result.Findings.Length)));
         for Finding of Result.Findings loop
            Add ("finding.indicator", Ada_Quality.Types.Image (Finding.Indicator));
            Add ("finding.rule", To_String (Finding.Rule));
            Add ("finding.severity", Ada_Quality.Types.Severity'Image (Finding.Level));
            Add ("finding.message", To_String (Finding.Message));
            Add ("finding.path", To_String (Finding.Relative_Path));
            Add ("finding.line", Natural'Image (Finding.Line));
            Add ("finding.fingerprint", To_String (Finding.Fingerprint));
         end loop;
      end loop;
      return Improve.Canonical_Digests.Finish (Digest, "assessment-sha256-v1:");
   end Assessment_Fingerprint;

   function Name_Of (Path : String) return String is
   begin
      return Ada.Directories.Simple_Name (Path);
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error => return Path;
   end Name_Of;

   function Resolve_Project (Item : Repository; Selector : String) return Improve.Model.Project_Reference is
      Matches    : Natural := 0;
      Found_Id   : Natural := 0;
      Found_Path : Unbounded_String;
      Numeric    : constant Boolean := Selector /= "" and then (for all C of Selector => C in '0' .. '9');
      Id         : Natural := 0;
   begin
      Require_Open (Item);
      if Selector = "" then raise Argument_Error with "project selector must not be empty"; end if;
      if Numeric then
         begin
            Id := Natural'Value (Selector);
         exception
            when Constraint_Error => raise Argument_Error with "project identity is out of range: " & Selector;
         end;
      end if;
      for Project of Ada_Quality.Reporting.Projects (Item.Session) loop
         declare Path : constant String := To_String (Project.Path); begin
            if (Numeric and then Id = Project.Id) or else
              (not Numeric and then (Selector = Path or else Selector = Name_Of (Path)))
            then
               Found_Id := Project.Id;
               Found_Path := Project.Path;
               Matches := Matches + 1;
            end if;
         end;
      end loop;
      if Matches = 0 then
         raise Argument_Error with "unknown project " & Selector;
      elsif Matches > 1 then
         raise Argument_Error with "project name is ambiguous: " & Selector;
      end if;
      return
        (Id   => Positive (Found_Id),
         Name => To_Unbounded_String (Name_Of (To_String (Found_Path))),
         Path => Found_Path,
         Database_Id => Item.Database_Id);
   end Resolve_Project;

   procedure Validate (Value : Ada_Quality.Reporting.Assessment_Record) is
   begin
      if Value.Results.Length /= 33 then
         raise Data_Error with "assessment does not contain exactly 33 indicator results";
      end if;
      declare Index : Positive := Value.Results.First_Index; begin
         for Indicator in Ada_Quality.Types.Indicator_Id loop
            if Value.Results (Index).Indicator /= Indicator or else
              not Ada_Quality.Types.Is_Valid (Value.Results (Index))
            then
               raise Data_Error with "assessment indicator evidence is incomplete or out of registry order";
            end if;
            Index := Index + 1;
         end loop;
      end;
   end Validate;

   function Latest_Completed_Run
     (Item    : Repository;
      Project : Improve.Model.Project_Reference) return Natural is
      Result : Natural := 0;
   begin
      Require_Open (Item);
      for Run of Ada_Quality.Reporting.Runs (Item.Session, Project.Id) loop
         if Run.State = Ada_Quality.Types.Assessment_Completed then
            Result := Natural'Max (Result, Run.Id);
         end if;
      end loop;
      return Result;
   exception
      when Error : Ada_Quality.Reporting.Reporting_Error =>
         raise Dependency_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Integrity_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Latest_Completed_Run;

   function Select_Assessment
     (Item       : Repository;
      Project    : Improve.Model.Project_Reference;
      Run_Id     : Natural := 0;
      Maximum_Bytes : Positive := Positive'Last) return Selection is
      Selected : Natural := (if Run_Id = 0 then Latest_Completed_Run (Item, Project) else 0);
   begin
      Require_Open (Item);
      for Run of Ada_Quality.Reporting.Runs (Item.Session, Project.Id) loop
         if Run_Id > 0 and then Run.Id = Run_Id and then Run.State = Ada_Quality.Types.Assessment_Completed
         then
            Selected := Run.Id;
         end if;
      end loop;
      if Selected = 0 then
         if Run_Id = 0 then
            raise Dependency_Error with "project has no completed quality assessment: " & To_String (Project.Name);
         else
            raise Dependency_Error with
              "run is missing, incomplete, or belongs to another project:" & Natural'Image (Run_Id);
         end if;
      end if;
      declare
         Assessment : constant Ada_Quality.Reporting.Assessment_Record :=
           Ada_Quality.Reporting.Read_Assessment (Item.Session, Positive (Selected));
      begin
         Validate (Assessment);
         return
           (Project    => Project,
            Assessment => Assessment,
            Baseline   =>
              (Project_Id   => Project.Id,
               Run_Id       => Assessment.Run.Id,
               Source_Id    => Assessment.Run.Source_Id,
               Policy_Id    => Assessment.Run.Policy_Id,
               Toolchain_Id => Assessment.Run.Toolchain_Id,
               Evidence_Id  => To_Unbounded_String (Assessment_Fingerprint (Assessment, Maximum_Bytes)),
               Snapshot_Id  => To_Unbounded_String (Identity (Item))));
      end;
   exception
      when Error : Ada_Quality.Reporting.Reporting_Error =>
         raise Dependency_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Integrity_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Select_Assessment;
end Improve.Source;

