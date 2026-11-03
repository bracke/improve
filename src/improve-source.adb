with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Containers.Vectors;
with Interfaces;
with Ada_Quality.Types;
with Project_Tools.Files;

package body Improve.Source is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Assessment_Status;
   use type Ada_Quality.Types.Indicator_Id;
   use type Interfaces.Unsigned_64;

   function Working_Fingerprint (Root : String) return String is
      package Paths is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String,
         "=" => Ada.Strings.Unbounded."=");
      package Sorting is new Paths.Generic_Sorting ("<" => Ada.Strings.Unbounded."<");
      Skip : constant Project_Tools.Files.Name_List :=
        [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
         To_Unbounded_String (".model_runner"), To_Unbounded_String ("obj"),
         To_Unbounded_String ("bin"), To_Unbounded_String ("cov-obj"),
         To_Unbounded_String ("cov-bin"), To_Unbounded_String ("coverage"),
         To_Unbounded_String ("lib"), To_Unbounded_String ("gnatprove")];
      Listed : constant Project_Tools.Files.Path_List := Project_Tools.Files.List_Tree (Root, "*", Skip);
      Values : Paths.Vector;
      Hash   : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Prime  : constant Interfaces.Unsigned_64 := 16#100000001B3#;
      Total  : Natural := 0;

      procedure Add (Text : String) is
      begin
         for C of Text loop
            Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * Prime;
         end loop;
      end Add;

      function Hex return String is
         Hex_Chars : constant String := "0123456789abcdef";
         Work   : Interfaces.Unsigned_64 := Hash;
         Result : String (1 .. 16);
      begin
         for Index in reverse Result'Range loop
            Result (Index) := Hex_Chars (Natural (Work and 16#F#) + 1);
            Work := Interfaces.Shift_Right (Work, 4);
         end loop;
         return Result;
      end Hex;

      function Runtime_Database (Path : String) return Boolean is
        ((Path'Length >= 3 and then Path (Path'Last - 2 .. Path'Last) = ".db") or else
         (Path'Length >= 7 and then Path (Path'Last - 6 .. Path'Last) = ".db.fts") or else
         (Path'Length >= 7 and then Path (Path'Last - 6 .. Path'Last) = ".sqlite") or else
         (Path'Length >= 8 and then Path (Path'Last - 7 .. Path'Last) = ".sqlite3"));
   begin
      if Listed'Length > 100_000 then raise Data_Error with "project source exceeds fingerprint file limit"; end if;
      for Path of Listed loop Values.Append (Path); end loop;
      Sorting.Sort (Values);
      for Path of Values loop
         declare
            Full : constant String := To_String (Path);
            Name : constant String :=
              (if Full'Length > Root'Length and then Full (Full'First .. Full'First + Root'Length - 1) = Root
               then Full (Full'First + Root'Length + 1 .. Full'Last)
               else Full);
         begin
            if Runtime_Database (Full) then
               null;
            else
               declare Data : constant String := Project_Tools.Files.Read_Raw_File (Full); begin
                  if Data'Length > 16_777_216 or else Total > 268_435_456 - Data'Length then
                     raise Data_Error with "project source exceeds fingerprint byte limit";
                  end if;
                  Total := Total + Data'Length;
                  Add (Name & Character'Val (0) & Data);
               end;
            end if;
         end;
      end loop;
      return "working-fnv1a64:" & Hex;
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

   function Select_Assessment
     (Item       : Repository;
      Project    : Improve.Model.Project_Reference;
      Run_Id     : Natural := 0) return Selection is
      Selected : Natural := 0;
   begin
      Require_Open (Item);
      for Run of Ada_Quality.Reporting.Runs (Item.Session, Project.Id) loop
         if (Run_Id = 0 and then Run.State = Ada_Quality.Types.Assessment_Completed) or else
           (Run_Id > 0 and then Run.Id = Run_Id and then Run.State = Ada_Quality.Types.Assessment_Completed)
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

