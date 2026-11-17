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
   declare
      Conflict_Path : constant String := Root & "/conflicting-links.db";
      Conflict_Plan : Improve.Model.Plan_Revision := Fixture (Root);
      Inline        : Improve.Model.UString_Vectors.Vector;
   begin
      Conflict_Plan.Tasks (2).Dependencies.Append (Conflict_Plan.Tasks (1).Id);
      Improve.Storage.Open (Store, Conflict_Path, Writable => True);
      Seed (Store, Conflict_Plan, 1, Stored);
      Improve.Storage.Close (Store);
      Inline.Append (Stored.Tasks (1).Id);
      Append_Task_Payload_Field
        (Conflict_Path, Task_Row => 2, Name => "dependencies",
         Value => Improve.Storage_Codec.Pack (Inline));
      Improve.Storage.Open (Store, Conflict_Path, Writable => False);
      Rejected := False;
      begin
         Stored := Improve.Storage.Load (Store, "PLAN-000001");
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "storage accepted inline and normalized dependency representations");
      Improve.Storage.Close (Store);
   end;
   declare
      State_Path : constant String := Root & "/invalid-link-state.db";
      State_Plan : Improve.Model.Plan_Revision := Fixture (Root);
   begin
      State_Plan.Tasks (2).Dependencies.Append (State_Plan.Tasks (1).Id);
      Improve.Storage.Open (Store, State_Path, Writable => True);
      Seed (Store, State_Plan, 1, Stored);
      Improve.Storage.Close (Store);
      Replace_Row_State (State_Path, Table => 9, Id => 1, State => "ignored");
      Improve.Storage.Open (Store, State_Path, Writable => False);
      Rejected := False;
      begin
         Stored := Improve.Storage.Load (Store, "PLAN-000001");
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "storage accepted a task dependency with noncanonical state");
      Improve.Storage.Close (Store);
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Corrupt_Links;
