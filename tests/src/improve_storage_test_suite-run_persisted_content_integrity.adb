separate (Improve_Storage_Test_Suite)
procedure Run_Persisted_Content_Integrity is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-content");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Task_Ids : Improve.Model.UString_Vectors.Vector;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Improve.Storage.Approve (Store, To_String (Stored.Plan_Id), Stored.Revision);
   Improve.Storage.Close (Store);
   Replace_Row_Payload (Path, Table => 13, Id => 1, Payload => "altered approved goal");
   Improve.Storage.Open (Store, Path, Writable => True);
   Assert
     (not Improve.Storage.Is_Approved (Store, To_String (Stored.Plan_Id), Stored.Revision),
      "altered persisted plan content retained its approval");
   Task_Ids.Append (Stored.Tasks.First_Element.Id);
   begin
      declare
         Operation : constant Positive :=
           Improve.Storage.Begin_Publication (Store, Stored, "remediation", Task_Ids);
      begin
         pragma Unreferenced (Operation);
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "publication accepted plan content that differs from durable state");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Persisted_Content_Integrity;
