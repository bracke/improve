with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Project_Tools.Files;

package body Improve_Check_All_Support is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String);

   procedure Validate_Dependency_Lock (Failed : in out Boolean) is
      Text  : constant String := Project_Tools.Files.Read_Raw_File (".github/dependency-lock.txt");
      Lines : Text_Vectors.Vector;
      Start : Natural := Text'First;
      Repositories : constant Text_Vectors.Vector :=
        [To_Unbounded_String ("ada_quality"), To_Unbounded_String ("database"),
         To_Unbounded_String ("jsonlib"), To_Unbounded_String ("messages"),
         To_Unbounded_String ("terminal_styles"), To_Unbounded_String ("project_tools"),
         To_Unbounded_String ("hostkit"), To_Unbounded_String ("model_runner"),
         To_Unbounded_String ("cryptolib"), To_Unbounded_String ("i18n"),
         To_Unbounded_String ("regexp"), To_Unbounded_String ("httpclient"),
         To_Unbounded_String ("ssllib"), To_Unbounded_String ("truststores"),
         To_Unbounded_String ("zlib"), To_Unbounded_String ("jpeglib"),
         To_Unbounded_String ("versionlib"), To_Unbounded_String ("sshlib"),
         To_Unbounded_String ("awklib")];

      procedure Report (Message : String) is
      begin
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "dependency lock: " & Message);
         Failed := True;
      end Report;

      procedure Require_Repository (Name : String) is
         Matches : Natural := 0;
      begin
         for Line of Lines loop
            declare
               Value : constant String := To_String (Line);
            begin
               if Value'Length > Name'Length and then
                 Value (Value'First .. Value'First + Name'Length) = Name & "="
               then
                  Matches := Matches + 1;
               end if;
            end;
         end loop;
         if Matches /= 1 then
            Report (Name & " must have exactly one pinned revision");
         end if;
      end Require_Repository;
   begin
      while Start <= Text'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
               Stop := Stop + 1;
            end loop;
            if Stop > Start then
               Lines.Append (To_Unbounded_String (Text (Start .. Stop - 1)));
            end if;
            Start := Stop + 1;
         end;
      end loop;
      if Lines.Length /= Repositories.Length then
         Report
           ("expected" & Natural'Image (Natural (Repositories.Length)) &
            " workspace repositories, found" & Natural'Image (Natural (Lines.Length)));
      end if;
      for Line of Lines loop
         declare
            Value : constant String := To_String (Line);
            Equal : Natural := 0;
         begin
            for Index in Value'Range loop
               if Value (Index) = '=' then
                  Equal := Index;
                  exit;
               end if;
            end loop;
            if Equal = 0 or else Value'Last - Equal /= 40 or else
              (for some Index in Equal + 1 .. Value'Last =>
                 Value (Index) not in '0' .. '9' | 'a' .. 'f')
            then
               Report ("invalid repository=commit entry: " & Value);
            end if;
         end;
      end loop;
      for Repository of Repositories loop
         Require_Repository (To_String (Repository));
      end loop;
   end Validate_Dependency_Lock;
end Improve_Check_All_Support;
