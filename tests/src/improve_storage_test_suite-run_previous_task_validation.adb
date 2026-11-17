separate (Improve_Storage_Test_Suite)
procedure Run_Previous_Task_Validation is
   Root     : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-previous-task");
   Store    : Improve.Storage.Store;
   Stored   : Improve.Model.Plan_Revision;
   Rejected : Boolean := False;
begin
   declare
      Path      : constant String := Root & "/conflict.db";
      Prior     : Improve.Model.Plan_Revision := Fixture (Root);
      Candidate : Improve.Model.Plan_Revision := Fixture (Root);
   begin
      Improve.Storage.Open (Store, Path, Writable => True);
      Seed (Store, Prior, 1, Stored);
      Improve.Storage.Close (Store);
      Append_Task_Payload_Field
        (Path, Task_Row => 1, Name => "acceptance", Value => "conflicting inline acceptance");
      Improve.Storage.Open (Store, Path, Writable => True);
      Candidate.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("revision after conflicting previous task"));
      begin
         declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Candidate); begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "plan persistence accepted conflicting previous task representations");
      Improve.Storage.Close (Store);
   end;
   declare
      Path      : constant String := Root & "/oversized.db";
      Prior     : Improve.Model.Plan_Revision := Fixture (Root);
      Candidate : Improve.Model.Plan_Revision := Fixture (Root);
      Limits    : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
   begin
      Improve.Storage.Open (Store, Path, Writable => True);
      Seed (Store, Prior, 1, Stored);
      Improve.Storage.Close (Store);
      Replace_Row_Payload (Path, Table => 7, Id => 1, Payload => [1 .. 600 => 'x']);
      Improve.Storage.Open (Store, Path, Writable => True);
      Candidate.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("revision after oversized previous task"));
      Limits.Maximum_Text_Bytes := 512;
      Rejected := False;
      begin
         declare Saved : constant Improve.Storage.Save_Result :=
           Improve.Storage.Save (Store, Candidate, Limits);
         begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Error : Improve.Data_Error =>
            Rejected := Ada.Exceptions.Exception_Message (Error) =
              "previous task payload exceeds configured persisted-text limit";
      end;
      Assert (Rejected, "previous-task payload was parsed before its configured limit was enforced");
      Improve.Storage.Close (Store);
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Previous_Task_Validation;
