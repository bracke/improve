with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.OS_Lib;
with Hostkit.Regular_Files;
with Improve.Presentation;

package body Improve.CLI_Support is
   use Ada.Strings.Unbounded;
   use Improve.CLI;
   use Improve.Config;
   use type Ada.Containers.Count_Type;

   LF : constant Character := Character'Val (10);

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   procedure Require_Output_Items
     (Count : Ada.Containers.Count_Type;
      Limit : Positive;
      Name  : String) is
   begin
      if Count > Ada.Containers.Count_Type (Limit) then
         raise Data_Error with Name & " exceeds output.maximum_output_items";
      end if;
   end Require_Output_Items;

   function Page_Limit
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return Positive is
   begin
      if Item.Has_Limit and then Item.Limit > Settings.Maximum_Output_Items then
         raise Argument_Error with "--limit exceeds output.maximum_output_items";
      end if;
      return (if Item.Has_Limit then Item.Limit else Settings.Maximum_Output_Items);
   end Page_Limit;

   function Query_Maximum
     (Item           : Improve.CLI.Invocation;
      Settings       : Improve.Config.Settings;
      Paged_Maximum  : Positive) return Positive is
     (if Item.Has_Limit or else Item.Has_Cursor then Paged_Maximum
      else Settings.Maximum_Output_Items);

   function Quality_Path
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return String is
     (if Item.Has_Database
      then To_String (Item.Database)
      else To_String (Settings.Quality_Database));

   function State_Path (Item : Improve.CLI.Invocation) return String is
     (if Item.Has_State then To_String (Item.State) else ".improve.db");

   function Read_Bounded_File
     (Path          : String;
      Description   : String;
      Maximum_Bytes : Positive;
      Observer      : Read_Observer := null) return String is
      package OS renames GNAT.OS_Lib;
      use type OS.File_Descriptor;
      use type OS.Large_File_Size;
      use type OS.OS_Time;

      File           : OS.File_Descriptor := OS.Invalid_FD;
      Supported      : Boolean;
      Initial_Length : OS.Large_File_Size;
      Initial_Time   : OS.OS_Time;
      Result         : Unbounded_String;
      Total          : Natural := 0;
      Buffer         : String (1 .. 64 * 1_024);
      Count          : Integer;

      procedure Close_File is
      begin
         if File /= OS.Invalid_FD then
            OS.Close (File);
            File := OS.Invalid_FD;
         end if;
      end Close_File;

      function Metadata_Changed return Boolean is
        (OS.File_Length64 (File) /= Initial_Length or else
         (Initial_Time /= OS.Invalid_Time and then OS.File_Time_Stamp (File) /= Initial_Time));
   begin
      File := Hostkit.Regular_Files.Open_Read (Path, Follow_Links => True, Supported => Supported);
      if not Supported or else File = OS.Invalid_FD then
         raise Dependency_Error with Description & " is unavailable or is not a regular file";
      end if;
      Initial_Length := OS.File_Length64 (File);
      Initial_Time := OS.File_Time_Stamp (File);
      if Initial_Length < 0 then
         raise Dependency_Error with Description & " size is unavailable";
      elsif Initial_Length > OS.Large_File_Size (Maximum_Bytes) then
         raise Argument_Error with Description & " exceeds the maximum supported size";
      end if;
      loop
         Count := OS.Read (File, Buffer'Address, Buffer'Length);
         if Count < 0 then
            raise Dependency_Error with Description & " could not be read completely";
         end if;
         exit when Count = 0;
         if Count > Maximum_Bytes - Total then
            raise Argument_Error with Description & " exceeds the maximum supported size";
         end if;
         Append (Result, Buffer (1 .. Count));
         Total := Total + Count;
      end loop;
      if OS.Large_File_Size (Total) /= Initial_Length or else Metadata_Changed then
         raise Dependency_Error with Description & " changed while it was being read";
      end if;
      if Observer /= null then
         Observer (1);
      end if;
      OS.Lseek (File, 0, OS.Seek_Set);
      declare
         Text     : constant String := To_String (Result);
         Position : Natural := 0;
      begin
         loop
            Count := OS.Read (File, Buffer'Address, Buffer'Length);
            if Count < 0 then
               raise Dependency_Error with Description & " could not be reread completely";
            end if;
            exit when Count = 0;
            if Count > Text'Length - Position or else
              Buffer (1 .. Count) /= Text (Text'First + Position .. Text'First + Position + Count - 1)
            then
               raise Dependency_Error with Description & " changed while it was being read";
            end if;
            Position := Position + Count;
         end loop;
         if Position /= Text'Length or else Metadata_Changed then
            raise Dependency_Error with Description & " changed while it was being read";
         end if;
         Close_File;
         return Text;
      end;
   exception
      when Argument_Error | Dependency_Error =>
         Close_File;
         raise;
      when others =>
         Close_File;
         raise;
   end Read_Bounded_File;

   function Read_Hex_Key
     (Path        : String;
      Description : String) return String is
      Text : constant String := Read_Bounded_File (Path, Description, 256);
      Last : Natural := Text'Last;
   begin
      while Text'Length > 0 and then Last >= Text'First and then
        Text (Last) in LF | Character'Val (13)
      loop
         if Last = Text'First then return ""; end if;
         Last := Last - 1;
      end loop;
      return (if Text = "" then "" else Text (Text'First .. Last));
   end Read_Hex_Key;

   function Render_Terminal
     (Item     : Improve.CLI.Invocation;
      Renderer : not null access function return String) return String is
      Style : Improve.Presentation.Styling_Scope :=
        Improve.Presentation.Configure (Item.Format, Item.Color);
      pragma Unreferenced (Style);
   begin
      declare
         Rendered : constant String := Renderer.all;
      begin
         if Item.Format = Markdown_Format then
            return
              "# Improve " & Name (Item.Command) & LF & LF
              & "```text" & LF & Rendered & "```" & LF;
         end if;
         return Rendered;
      end;
   end Render_Terminal;
end Improve.CLI_Support;
