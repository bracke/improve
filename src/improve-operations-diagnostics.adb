with Ada.Directories;
with Ada.Exceptions;
with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Source;
with Improve.State;
with Project_Tools.Alire_Manifests;
with Project_Tools.Files;
with Project_Tools.Processes;

package body Improve.Operations.Diagnostics is
   use Ada.Strings.Unbounded;
   use type Improve.Results.Diagnostic_Status;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Run
     (Quality_Path     : String;
      State_Path       : String;
      Project_Selector : String;
      Settings         : Improve.Config.Settings;
      Resolve_Release  : Boolean := False;
      Limits           : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Results.Diagnostic_Report is
      Result : Improve.Results.Diagnostic_Report;
      Release_Manifest : constant String :=
        (if Ada.Directories.Exists ("alire.release.toml") and then
             Project_Tools.Files.File_Contains ("alire.release.toml", "name = ""improve""")
         then "alire.release.toml"
         elsif Ada.Directories.Exists ("../alire.release.toml") and then
           Project_Tools.Files.File_Contains ("../alire.release.toml", "name = ""improve""")
         then "../alire.release.toml"
         else "");

      procedure Add
        (Name   : String;
         Status : Improve.Results.Diagnostic_Status;
         Detail : String) is
      begin
         Result.Checks.Append
           (Improve.Results.Diagnostic_Check'
              (Name   => To_Unbounded_String (Name),
               Status => Status,
               Detail => To_Unbounded_String (Detail)));
         if Status = Improve.Results.Diagnostic_Fail then Result.Healthy := False; end if;
      end Add;

      procedure Check_Release_Resolution is
         Stamp : String := Duration'Image (Ada.Calendar.Seconds (Ada.Calendar.Clock));
      begin
         for C of Stamp loop
            if C not in '0' .. '9' then C := '_'; end if;
         end loop;
         declare
            Stage : constant String := Project_Tools.Files.Temp_Dir & "/improve-release-doctor-" & Stamp;
            Alr   : constant String := Project_Tools.Processes.Locate_Command ("alr");
         begin
            if Alr = "" then
               Add ("release-resolution", Improve.Results.Diagnostic_Fail, "Alire is unavailable");
               return;
            end if;
            Ada.Directories.Create_Directory (Stage);
            Ada.Directories.Copy_File (Release_Manifest, Stage & "/alire.toml");
            declare
               Run : constant Project_Tools.Processes.Captured_Process :=
                 Project_Tools.Processes.Capture
                   ("release dependency resolution", Stage, Alr,
                    Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("-n"),
                        Project_Tools.Processes.Argument ("show"),
                        Project_Tools.Processes.Argument ("--solve")]),
                    Quiet => True);
            begin
               if Run.Status = 0 then
                  Add ("release-resolution", Improve.Results.Diagnostic_Pass, "pin-free dependencies resolve");
               else
                  Add ("release-resolution", Improve.Results.Diagnostic_Fail, "Alire could not resolve dependencies");
               end if;
            end;
            Ada.Directories.Delete_Tree (Stage);
         exception
            when Error : others =>
               if Ada.Directories.Exists (Stage) then Ada.Directories.Delete_Tree (Stage); end if;
               Add ("release-resolution", Improve.Results.Diagnostic_Fail, Ada.Exceptions.Exception_Message (Error));
         end;
      end Check_Release_Resolution;
   begin
      Add ("configuration", Improve.Results.Diagnostic_Pass, "effective configuration is valid");
      Add
        ("workflow-task-kind", Improve.Results.Diagnostic_Pass,
         "configured native task kind is " & To_String (Settings.Task_Kind));
      if Quality_Path = "" or else not Ada.Directories.Exists (Quality_Path) then
         Add ("quality-database", Improve.Results.Diagnostic_Fail, "selected database does not exist");
      else
         declare Quality : Improve.Source.Repository; begin
            Improve.Source.Open
              (Quality, Quality_Path, Improve.Operations.Quality_Load_Limits (Settings),
               Settings.Maximum_Quality_Database_Bytes);
            if Project_Selector /= "" then
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Project_Selector);
               begin
                  Add
                    ("quality-project", Improve.Results.Diagnostic_Pass,
                     "resolved project " & To_String (Project.Name));
               end;
            end if;
            Improve.Source.Close (Quality);
            Add ("quality-database", Improve.Results.Diagnostic_Pass, "read-only reporting session opened");
         exception
            when Error : others =>
               Add
                 ("quality-database", Improve.Results.Diagnostic_Fail,
                  Ada.Exceptions.Exception_Message (Error));
         end;
      end if;
      if State_Path = "" or else not Ada.Directories.Exists (State_Path) then
         Add ("improve-state", Improve.Results.Diagnostic_Warning, "state database does not exist");
      else
         declare State : Improve.Storage.Store; begin
            Improve.Storage.Open (State, State_Path, Writable => False, Limits => Limits);
            declare
               Pending : constant Improve.State.Publication_Operation_Vectors.Vector :=
                 Improve.Storage.Pending_Publications
                   (State, Settings.Maximum_Recovery_Operations, Limits);
            begin
               Add
                 ("pending-recovery", Improve.Results.Diagnostic_Pass,
                  Number (Natural (Pending.Length)) & " pending publication operations");
            end;
            Improve.Storage.Close (State);
            Add ("improve-state", Improve.Results.Diagnostic_Pass, "read-only state session opened");
         exception
            when Error : others =>
               Add
                 ("improve-state", Improve.Results.Diagnostic_Fail,
                  Ada.Exceptions.Exception_Message (Error));
         end;
      end if;
      if Release_Manifest /= "" then
         begin
            Project_Tools.Alire_Manifests.Require_Pin_Free_Crate_Manifest
              (Release_Manifest, "improve", Quiet => True);
            if not Project_Tools.Files.File_Contains
              (Release_Manifest, "gnat_native = ""=15.2.1""")
            then
               Add
                 ("release-toolchain", Improve.Results.Diagnostic_Fail,
                  "release manifest does not pin gnat_native 15.2.1");
            else
               Add
                 ("release-toolchain", Improve.Results.Diagnostic_Pass,
                  "release manifest pins gnat_native 15.2.1");
            end if;
            Add
              ("release-manifest", Improve.Results.Diagnostic_Pass,
               "release manifest is pin-free and names crate improve");
         exception
            when Error : others =>
               Add
                 ("release-manifest", Improve.Results.Diagnostic_Fail,
                  Ada.Exceptions.Exception_Message (Error));
         end;
      else
         Add ("release-manifest", Improve.Results.Diagnostic_Warning, "alire.release.toml is unavailable here");
      end if;
      if Resolve_Release then
         if Release_Manifest = "" then
            Add ("release-resolution", Improve.Results.Diagnostic_Fail, "release manifest is unavailable");
         else
            Check_Release_Resolution;
         end if;
      end if;
      return Result;
   end Run;
end Improve.Operations.Diagnostics;
