with Ada.Strings.Unbounded;

--  Transactional publication for generated CLI integration assets.
generic
   Lock_Path : String;
   with function Replace_File (Source, Target : String) return Boolean;
   with procedure Write_File (Path, Content : String);
   with procedure Copy_File (Source, Target : String);
   with procedure Delete_File (Path : String);
package Improve_CLI_Asset_Publication is
   type Asset_Array is array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;

   --  Replace every target atomically, restoring only targets already replaced if publication fails.
   procedure Publish (Paths, Contents : Asset_Array)
     with Pre => Paths'Length > 0 and then Paths'First = Contents'First and then Paths'Last = Contents'Last;
end Improve_CLI_Asset_Publication;
