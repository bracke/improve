separate (Improve_Storage_Test_Suite)
procedure Run_Corrupt_Provenance is
   Root          : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-provenance");
   Path          : constant String := Root & "/state.db";
   Store         : Improve.Storage.Store;
   Plan          : Improve.Model.Plan_Revision := Fixture (Root);
   Stored        : Improve.Model.Plan_Revision;
   Load_Rejected : Boolean := False;
   List_Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Corrupt_Baseline_Parent (Path, Baseline_Id => 1);
   Improve.Storage.Open (Store, Path, Writable => False);
   begin
      Stored := Improve.Storage.Load (Store, "PLAN-000001", 1);
   exception
      when Improve.Data_Error => Load_Rejected := True;
   end;
   begin
      declare Values : constant Improve.State.Summary_Vectors.Vector :=
        Improve.Storage.List (Store, Plan.Project);
      begin
         pragma Unreferenced (Values);
      end;
   exception
      when Improve.Data_Error => List_Rejected := True;
   end;
   Assert
     (Load_Rejected and then List_Rejected,
      "full and summary reads did not enforce the same provenance relationships");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Corrupt_Provenance;
