separate (Improve_Storage_Test_Suite)
procedure Run_Schema_Migration is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-migration");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Mappings : Improve.Storage.Publication_Vectors.Vector;
   Evidence : Improve.Storage.Verification_Vectors.Vector;
   Limits   : constant Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
begin
   Improve.Storage.Open (Store, Path, Writable => True, Limits => Limits);
   Seed (Store, Plan, 4, Stored, Limits);
   History_Records (Stored, Mappings, Evidence);
   Improve.Storage.Record_Publications (Store, To_String (Stored.Plan_Id), Mappings, Limits);
   Improve.Storage.Record_Verification (Store, To_String (Stored.Plan_Id), Evidence, Limits);
   Improve.Storage.Close (Store);
   Downgrade_To_Version_2 (Path);
   declare
      Too_Small : Improve.Storage.Read_Limits := Limits;
      Rejected  : Boolean := False;
   begin
      Too_Small.Maximum_History := 3;
      begin
         Improve.Storage.Open (Store, Path, Writable => True, Limits => Too_Small);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "schema migration ignored its configured history limit");
   end;
   Improve.Storage.Open (Store, Path, Writable => True, Limits => Limits);
   Assert
     (Improve.Storage.Publications (Store, To_String (Stored.Plan_Id)).Length = 2 and then
      Improve.Storage.Verifications (Store, To_String (Stored.Plan_Id)).Length = 2,
      "schema migration did not preserve indexed history");
   declare
      Migrated : constant Improve.Model.Plan_Revision :=
        Improve.Storage.Load_Task (Store, To_String (Stored.Tasks.First_Element.Id), Limits => Limits);
      Summaries : constant Improve.Storage.Summary_Vectors.Vector :=
        Improve.Storage.List (Store, Stored.Project, Limits => Limits);
   begin
      Assert (Migrated.Revision = Stored.Revision, "migration lost historical task lookup");
      Assert
        (Summaries.Length = 1 and then Summaries.First_Element.Project_Id = Stored.Project.Id and then
         Summaries.First_Element.Run_Id = Stored.Baseline.Run_Id,
         "migration did not preserve normalized summary provenance");
   end;
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Schema_Migration;
