separate (Improve_Storage_Test_Suite)
procedure Run_Identity_Exhaustion is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-identity");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Close (Store);
   Exhaust_Project_Identities (Path);
   Improve.Storage.Open (Store, Path, Writable => True);
   Plan.Project :=
     (Id          => 2,
      Name        => To_Unbounded_String ("identity-limit"),
      Path        => To_Unbounded_String (Root & "/identity-limit"),
      Database_Id => To_Unbounded_String (Root & "/other-quality.db"));
   Plan.Baseline.Project_Id := 2;
   Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("identity limit revision"));
   begin
      declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan); begin
         pragma Unreferenced (Saved);
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "storage accepted an identity outside its namespace");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Identity_Exhaustion;
