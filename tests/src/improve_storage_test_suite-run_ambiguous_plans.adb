separate (Improve_Storage_Test_Suite)
procedure Run_Ambiguous_Plans is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-ambiguous-plan");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Duplicate_Plan (Path, Positive (Stored.Tasks.Length));
   Improve.Storage.Open (Store, Path, Writable => False);
   begin
      declare
         Values : constant Improve.Storage.Summary_Vectors.Vector :=
           Improve.Storage.List (Store, Stored.Project);
         pragma Unreferenced (Values);
      begin
         null;
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "ambiguous project plan identity was silently selected");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Ambiguous_Plans;
