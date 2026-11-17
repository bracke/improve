separate (Improve_Storage_Test_Suite)
procedure Run_Interleaved_History_Validation is
   Revision_Count : constant Positive := 5;
   Round_Count    : constant Positive := 2;
   Evidence_Count : constant Positive := Revision_Count * Round_Count;
   Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-interleaved-history");
   Path   : constant String := Root & "/state.db";
   Store  : Improve.Storage.Store;
   Plan   : Improve.Model.Plan_Revision := Fixture (Root);
   Stored : Improve.Model.Plan_Revision;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, Revision_Count, Stored);
   for Round in 1 .. Round_Count loop
      for Revision in 1 .. Revision_Count loop
         declare
            Exact    : constant Improve.Model.Plan_Revision :=
              Improve.Storage.Load (Store, To_String (Stored.Plan_Id), Revision);
            Contract : constant String :=
              Improve.Model.Effective_Task_Contract_Fingerprint (Exact, Exact.Tasks.First_Element.Id);
            Evidence : Improve.State.Verification_Vectors.Vector;
         begin
            Evidence.Append
              (Improve.State.Verification_Record'
                 (Scope                => Improve.Model.Task_Evaluation,
                  Task_Id              => Exact.Tasks.First_Element.Id,
                  Plan_Revision        => Revision,
                  Contract_Fingerprint => To_Unbounded_String (Contract),
                  Assessment_Id        => (Round - 1) * Revision_Count + Revision,
                  Outcome              => Improve.Model.Still_Failing,
                  Comparable           => True,
                  Explanation          => To_Unbounded_String ("interleaved revision evidence")));
            Improve.Storage.Record_Verification (Store, To_String (Stored.Plan_Id), Evidence);
         end;
      end loop;
   end loop;
   declare
      Limits : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Evidence : Improve.State.Verification_Vectors.Vector;
   begin
      --  Reading ten rows and loading each of the five distinct revisions once
      --  consumes exactly 10 + (1 + 2 + 3 + 4 + 5) history records. Reloading
      --  contracts for the second round would exceed this operation-wide budget.
      Limits.Maximum_History := Evidence_Count + Revision_Count * (Revision_Count + 1) / 2;
      Evidence := Improve.Storage.Verifications (Store, Limits => Limits);
      Assert
        (Evidence.Length = Ada.Containers.Count_Type (Evidence_Count),
         "grouped history validation lost interleaved revision evidence");
   end;
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Interleaved_History_Validation;
