separate (Improve_Storage_Test_Suite)
procedure Run_Corrupt_Revision_Data is
   Root          : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-revision");
   Path          : constant String := Root & "/state.db";
   Store         : Improve.Storage.Store;
   Plan          : Improve.Model.Plan_Revision := Fixture (Root);
   Stored        : Improve.Model.Plan_Revision;
   Rejected      : Boolean := False;
   Misclassified : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Corrupt_Revision (Path, 1);
   Improve.Storage.Open (Store, Path, Writable => False);
   begin
      Stored := Improve.Storage.Load (Store, "PLAN-000001");
   exception
      when Improve.Data_Error     => Rejected := True;
      when Improve.Argument_Error => Misclassified := True;
   end;
   Assert (Rejected and then not Misclassified, "corrupt revision was not classified as an integrity failure");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Corrupt_Revision_Data;
