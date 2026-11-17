separate (Improve_Storage_Test_Suite)
procedure Run_Ambiguous_Plans is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-ambiguous-plan");
   Path     : constant String := Root & "/state.db";
   Store    : Improve.Storage.Store;
   Plan     : Improve.Model.Plan_Revision := Fixture (Root);
   Stored   : Improve.Model.Plan_Revision;
   Mappings : Improve.State.Publication_Vectors.Vector;
   Evidence : Improve.State.Verification_Vectors.Vector;
   Limits   : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
   Rejected : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   History_Records (Stored, Mappings, Evidence);
   Improve.Storage.Record_Publications (Store, To_String (Stored.Plan_Id), Mappings);
   Improve.Storage.Record_Verification (Store, To_String (Stored.Plan_Id), Evidence);
   Improve.Storage.Close (Store);
   Duplicate_Plan (Path, Positive (Stored.Tasks.Length));
   Improve.Storage.Open (Store, Path, Writable => False);
   --  Two history rows plus one revision-contract lookup for each owning plan.
   Limits.Maximum_History := 4;
   Assert
     (Improve.Storage.Publications (Store, Maximum => 2, Limits => Limits).Length = 2,
      "exact-limit publication query was rejected by a later empty plan");
   Assert
     (Improve.Storage.Verifications (Store, Maximum => 2, Limits => Limits).Length = 2,
      "exact-limit verification query was rejected by a later empty plan");
   Assert
     (Improve.Storage.Verifications
        (Store, Task_Id => To_String (Stored.Tasks.First_Element.Id), Maximum => 1,
         Limits => Limits).Length = 1,
      "all-plan verification filtering did not select the requested task");
   begin
      declare
         Values : constant Improve.State.Summary_Vectors.Vector :=
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
