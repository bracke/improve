separate (Improve_Storage_Test_Suite)
procedure Run_Inactive_Persistence_Row is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-inactive-row");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Deactivate_Row (Path, Table => 7, Id => 1);
   begin
      Improve.Storage.Open (Store, Path, Writable => False);
      Stored := Improve.Storage.Load (Store, "PLAN-000001");
      Improve.Storage.Close (Store);
   exception
      when Improve.Data_Error =>
         Rejected := True;
         Improve.Storage.Close (Store);
   end;
   Assert (Rejected, "storage reconstructed an inactive task row");
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Inactive_Persistence_Row;
