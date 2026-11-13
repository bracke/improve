separate (Improve_Storage_Test_Suite)
procedure Run_Corrupt_Links is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-link");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Insert_Unknown_Finding_Link (Path, Task_Row => 1);
   Improve.Storage.Open (Store, Path, Writable => False);
   begin
      Stored := Improve.Storage.Load (Store, "PLAN-000001");
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "storage loaded a task link to an unknown finding");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Corrupt_Links;
