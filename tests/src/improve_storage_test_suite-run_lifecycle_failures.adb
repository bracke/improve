separate (Improve_Storage_Test_Suite)
procedure Run_Lifecycle_Failures is
   Root  : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-lifecycle");
   Path  : constant String := Root & "/state.db";
   Store : Improve.Storage.Store;
   Plan  : Improve.Model.Plan_Revision := Fixture (Root);
begin
   Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("lifecycle baseline"));
   declare
      Retry_Path  : constant String := Root & "/retry.db";
      Retry_Store : Improve.Storage.Store;
      Rejected    : Boolean := False;
   begin
      Database.Fault_Injection.Enable_Fault (Database.Fault_Injection.Fail_WAL_Flush);
      begin
         Improve.Storage.Open (Retry_Store, Retry_Path, Writable => True);
      exception
         when Improve.Data_Error =>
            Rejected := True;
      end;
      Database.Fault_Injection.Reset;
      Assert (Rejected, "initial schema commit fault was not reported");
      Improve.Storage.Open (Retry_Store, Retry_Path, Writable => True);
      Improve.Storage.Close (Retry_Store);
   exception
      when others =>
         Database.Fault_Injection.Reset;
         raise;
   end;
   Improve.Storage.Open (Store, Path, Writable => True);
   declare
      Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan);
   begin
      pragma Unreferenced (Saved);
   end;
   declare
      Candidate : Improve.Model.Plan_Revision := Plan;
      Rejected  : Boolean := False;
   begin
      Candidate.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("transaction commit failure"));
      Candidate.Tasks (Candidate.Tasks.First_Index).Goal := To_Unbounded_String
        ("A failed durable commit must not be reported as successful");
      Database.Fault_Injection.Enable_Fault (Database.Fault_Injection.Fail_WAL_Flush);
      begin
         declare
            Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Candidate);
         begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Improve.Data_Error =>
            Rejected := True;
      end;
      Database.Fault_Injection.Reset;
      Assert (Rejected, "storage ignored a durable transaction commit failure");
      Assert
        (not Improve.Storage.List_All (Store).Is_Empty,
         "storage was unusable after rolling back a failed commit");
   exception
      when others =>
         Database.Fault_Injection.Reset;
         raise;
   end;
   declare
      Rejected : Boolean := False;
      Closed   : Boolean := False;
   begin
      Database.Fault_Injection.Enable_Fault
        (Database.Fault_Injection.Partial_Metadata_Persistence);
      begin
         Improve.Storage.Close (Store);
      exception
         when Improve.Data_Error =>
            Rejected := True;
      end;
      Database.Fault_Injection.Reset;
      Assert (Rejected, "storage ignored a database close failure");
      begin
         declare Store_Id : constant String := Improve.Storage.Identity (Store); begin
            pragma Unreferenced (Store_Id);
         end;
      exception
         when Improve.Data_Error =>
            Closed := True;
      end;
      Assert (Closed, "storage retained an open-state flag after the database handle closed with an error");
   exception
      when others =>
         Database.Fault_Injection.Reset;
         raise;
   end;
   Improve.Storage.Open (Store, Path, Writable => True);
   declare
      Hold     : Improve.Storage.Lifecycle_Testing.Read_Hold;
      Rejected : Boolean := False;
   begin
      Improve.Storage.Lifecycle_Testing.Hold_Read (Store, Hold);
      begin
         Improve.Storage.Close (Store);
      exception
         when Improve.Data_Error =>
            Rejected := True;
      end;
      Assert (Rejected, "storage ignored a close refused by an active transaction");
      Assert
        (Improve.Storage.Identity (Store) /= "",
         "storage discarded its open state after the database refused to close");
      Improve.Storage.Lifecycle_Testing.Release (Hold);
   end;
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Database.Fault_Injection.Reset;
      begin
         Improve.Storage.Close (Store);
      exception
         when others =>
            null;
      end;
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Lifecycle_Failures;
