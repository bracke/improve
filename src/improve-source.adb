with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Containers.Vectors;
with Ada.Streams;
with Ada_Quality.Types;
with CryptoLib.Hashes;
with Hostkit.Directory_Listing;
with Hostkit.Fs;
with Project_Tools.Files;

package body Improve.Source is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Assessment_Status;
   use type Ada_Quality.Types.Indicator_Id;
   use type Hostkit.Directory_Listing.Entry_Kind;

   function Working_Fingerprint (Root : String) return String is
      package Paths is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String,
         "=" => Ada.Strings.Unbounded."=");
      package Sorting is new Paths.Generic_Sorting ("<" => Ada.Strings.Unbounded."<");
      Generated_Directories : constant Project_Tools.Files.Name_List :=
        [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
         To_Unbounded_String (".model_runner"), To_Unbounded_String ("obj"),
         To_Unbounded_String ("bin"), To_Unbounded_String ("cov-obj"),
         To_Unbounded_String ("cov-bin"), To_Unbounded_String ("coverage"),
         To_Unbounded_String ("gnatprove")];
      Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
      Values : Paths.Vector;
      Context : CryptoLib.Hashes.SHA256_Context;
      Total  : Natural := 0;

      function Skipped_Generated_Directory (Name : String) return Boolean is
      begin
         for Value of Generated_Directories loop
            if To_String (Value) = Name then
               return True;
            end if;
         end loop;
         return False;
      end Skipped_Generated_Directory;

      function Operational_File (Relative : String) return Boolean is
        (Relative = ".improve.db" or else Relative = ".improve.db.fts" or else
         Relative = ".improve.db-wal" or else Relative = ".improve.db-shm");

      procedure Walk (Directory, Relative_Directory : String) is
         Entries : Hostkit.Directory_Listing.Entry_Vectors.Vector;
      begin
         if not Hostkit.Directory_Listing.List (Directory, Entries) then
            raise Data_Error with "project source directory cannot be listed: " & Directory;
         end if;
         for Item of Entries loop
            declare
               Name     : constant String := Item.Name;
               Path     : constant String := Project_Tools.Files.Join (Directory, Name);
               Relative : constant String :=
                 (if Relative_Directory = "" then Name
                  else Relative_Directory & "/" & Name);
            begin
               if Item.Kind = Hostkit.Directory_Listing.Directory and then
                 Skipped_Generated_Directory (Name)
               then
                  null;
               elsif Item.Kind = Hostkit.Directory_Listing.Symbolic_Link or else Hostkit.Fs.Is_Link (Path) then
                  raise Data_Error with "project source contains a symbolic link: " & Relative;
               elsif Item.Kind = Hostkit.Directory_Listing.Directory then
                  Walk (Path, Relative);
               elsif Item.Kind = Hostkit.Directory_Listing.Regular_File and then not Operational_File (Relative) then
                  if Values.Length >= 100_000 then
                     raise Data_Error with "project source exceeds fingerprint file limit";
                  end if;
                  Values.Append (To_Unbounded_String (Relative));
               elsif Item.Kind = Hostkit.Directory_Listing.Unknown then
                  raise Data_Error with "project source entry kind cannot be established: " & Relative;
               end if;
            end;
         end loop;
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

      function Hex (Digest : CryptoLib.Hashes.SHA256_Digest) return String is
         Hex_Chars : constant String := "0123456789abcdef";
         Result : String (1 .. 64);
      begin
         for Index in Digest'Range loop
            Result (2 * Index - 1) := Hex_Chars (Natural (Digest (Index)) / 16 + 1);
            Result (2 * Index) := Hex_Chars (Natural (Digest (Index)) mod 16 + 1);
         end loop;
         return Result;
      end Hex;

      procedure Add_File (Relative : String) is
         Text    : Unbounded_String;
         Outcome : Hostkit.Fs.Read_Beneath_Outcome;
      begin
         Hostkit.Fs.Read_Beneath (Canonical_Root, Relative, 16_777_216, Text, Outcome);
         case Outcome is
            when Hostkit.Fs.Read_Done => null;
            when Hostkit.Fs.Read_Too_Large =>
               raise Data_Error with "project source exceeds fingerprint byte limit";
            when Hostkit.Fs.Read_Outside =>
               raise Data_Error with "project source contains an unsafe link: " & Relative;
            when others =>
               raise Data_Error with "project source changed or cannot be read: " & Relative;
         end case;
         if Total > 268_435_456 - Length (Text) then
            raise Data_Error with "project source exceeds fingerprint byte limit";
         end if;
         Add_Length (Length (Text));
         Add (To_String (Text));
         Total := Total + Length (Text);
      end Add_File;
   begin
      Walk (Canonical_Root, "");
      Sorting.Sort (Values);
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      Add ("improve-working-source-v3" & Character'Val (0));
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
      return "working-sha256-v3:" & Hex (CryptoLib.Hashes.Finalize (Context));
   end Working_Fingerprint;

   procedure Open
     (Item   : in out Repository;
      Path   : String;
      Limits : Ada_Quality.Reporting.Load_Limits := (others => <>)) is
   begin
      if Item.Opened then Close (Item); end if;
      Ada_Quality.Reporting.Open (Item.Session, Path, Limits);
      Item.Database_Id := To_Unbounded_String (Ada.Directories.Full_Name (Path));
      Item.Opened := True;
   exception
      when Error : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Busy_Error =>
         raise Dependency_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Schema_Error | Ada_Quality.Reporting.Integrity_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Limit_Error =>
         raise Data_Error with
           "quality snapshot exceeds configured limits: " & Ada.Exceptions.Exception_Message (Error);
   end Open;

   procedure Close (Item : in out Repository) is
   begin
      Ada_Quality.Reporting.Close (Item.Session);
      Item.Opened := False;
      Item.Database_Id := Null_Unbounded_String;
   end Close;

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
      Index : Positive := Value.Results.First_Index;
   begin
      if Value.Results.Length /= 33 then
         raise Data_Error with "assessment does not contain exactly 33 indicator results";
      end if;
      for Indicator in Ada_Quality.Types.Indicator_Id loop
         if Value.Results (Index).Indicator /= Indicator or else
           not Ada_Quality.Types.Is_Valid (Value.Results (Index))
         then
            raise Data_Error with "assessment indicator evidence is incomplete or out of registry order";
         end if;
         Index := Index + 1;
      end loop;
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
      Run_Id     : Natural := 0) return Selection is
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
               Snapshot_Id  => To_Unbounded_String (Identity (Item))));
      end;
   exception
      when Error : Ada_Quality.Reporting.Reporting_Error =>
         raise Dependency_Error with Ada.Exceptions.Exception_Message (Error);
      when Error : Ada_Quality.Reporting.Integrity_Error =>
         raise Data_Error with Ada.Exceptions.Exception_Message (Error);
   end Select_Assessment;
end Improve.Source;

