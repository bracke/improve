with Ada.Directories;
with Ada.Strings.Unbounded;
with Hostkit.Fs;
with Improve.CLI;
with Improve_CLI_Asset_Publication;
with Project_Tools.Files;

--  Regenerate committed command-line integration assets from CLI metadata.
procedure Generate_CLI_Surface is
   use Ada.Strings.Unbounded;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "improve.gpr");

   procedure Copy_Asset (Source, Target : String) is
   begin
      Ada.Directories.Copy_File (Source, Target);
   end Copy_Asset;

   procedure Delete_Asset (Path : String) is
   begin
      Ada.Directories.Delete_File (Path);
   end Delete_Asset;

   package Asset_Publication is new Improve_CLI_Asset_Publication
     (Lock_Path   => Root & "/improve.gpr",
      Replace_File => Hostkit.Fs.Replace_File,
      Write_File => Project_Tools.Files.Write_Raw_File,
      Copy_File  => Copy_Asset,
      Delete_File => Delete_Asset);

   function Arguments (First : String; Second : String := "") return Improve.CLI.String_Vectors.Vector is
      Result : Improve.CLI.String_Vectors.Vector;
   begin
      Result.Append (First);
      if Second /= "" then
         Result.Append (Second);
      end if;
      return Result;
   end Arguments;

   function Generate (Path, Command : String; Target : String := "") return String is
      Result : constant Improve.CLI.Outcome := Improve.CLI.Execute (Arguments (Command, Target));
   begin
      if Result.Exit_Code /= Improve.CLI.Success_Exit then
         raise Program_Error with "could not generate " & Path & ": " & To_String (Result.Errors);
      end if;
      return To_String (Result.Output);
   end Generate;
begin
   if Root = "" then
      raise Program_Error with "cannot locate Improve project root";
   end if;
   Ada.Directories.Set_Directory (Root);
   declare
      Bash_Path    : constant String := "completions/improve.bash";
      Zsh_Path     : constant String := "completions/_improve";
      Fish_Path    : constant String := "completions/improve.fish";
      Manpage_Path : constant String := "docs/improve.1";
      Bash_Text    : constant String := Generate (Bash_Path, "completion", "bash");
      Zsh_Text     : constant String := Generate (Zsh_Path, "completion", "zsh");
      Fish_Text    : constant String := Generate (Fish_Path, "completion", "fish");
      Manpage_Text : constant String := Generate (Manpage_Path, "manpage");
   begin
      Asset_Publication.Publish
        ([To_Unbounded_String (Bash_Path), To_Unbounded_String (Zsh_Path),
          To_Unbounded_String (Fish_Path), To_Unbounded_String (Manpage_Path)],
         [To_Unbounded_String (Bash_Text), To_Unbounded_String (Zsh_Text),
          To_Unbounded_String (Fish_Text), To_Unbounded_String (Manpage_Text)]);
   end;
end Generate_CLI_Surface;
