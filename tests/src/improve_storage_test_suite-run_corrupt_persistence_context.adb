separate (Improve_Storage_Test_Suite)
procedure Run_Corrupt_Persistence_Context is
   Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-context");

   procedure Expect_Data_Error
     (Action  : not null access procedure;
      Message : String) is
      Rejected : Boolean := False;
   begin
      begin
         Action.all;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, Message);
   end Expect_Data_Error;

   procedure Seed_One
     (Path   : String;
      Store  : in out Improve.Storage.Store;
      Stored : out Improve.Model.Plan_Revision) is
      Draft : Improve.Model.Plan_Revision := Fixture (Root);
   begin
      Improve.Storage.Open (Store, Path, Writable => True);
      Seed (Store, Draft, 1, Stored);
   end Seed_One;
begin
   declare
      Path   : constant String := Root & "/approval.db";
      Store  : Improve.Storage.Store;
      Stored : Improve.Model.Plan_Revision;

      procedure Read_Approval is
         Approved : constant Boolean :=
           Improve.Storage.Is_Approved (Store, "PLAN-000001", 1);
      begin
         pragma Unreferenced (Approved);
      end Read_Approval;
   begin
      Seed_One (Path, Store, Stored);
      Improve.Storage.Approve (Store, "PLAN-000001", 1);
      Improve.Storage.Close (Store);
      Replace_Row_Payload
        (Path, 12, 1,
         Improve.Persistence_Records.Encode_Approval
           ((Plan_Id     => To_Unbounded_String ("PLAN-999999"),
             Revision    => 1,
             Fingerprint => Stored.Fingerprint)));
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Approval'Access, "approval payload was not bound to its plan row context");
      Improve.Storage.Close (Store);
   end;
   declare
      Path     : constant String := Root & "/publication-contract.db";
      Store    : Improve.Storage.Store;
      Stored   : Improve.Model.Plan_Revision;
      Mappings : Improve.Storage.Publication_Vectors.Vector;
      Evidence : Improve.Storage.Verification_Vectors.Vector;

      procedure Read_Publications is
         Values : constant Improve.Storage.Publication_Vectors.Vector :=
           Improve.Storage.Publications (Store, "PLAN-000001");
      begin
         pragma Unreferenced (Values);
      end Read_Publications;
   begin
      Seed_One (Path, Store, Stored);
      History_Records (Stored, Mappings, Evidence);
      Improve.Storage.Record_Publications (Store, "PLAN-000001", Mappings);
      Improve.Storage.Close (Store);
      Replace_Row_Payload
        (Path, 10, 1,
         Improve.Persistence_Records.Encode_Publication
           ((Plan_Id       => To_Unbounded_String ("PLAN-000001"),
             Harness_Id    => Mappings (1).Harness_Task_Id,
             Origin        => Mappings (1).Origin,
             Contract      => To_Unbounded_String ("unrelated-contract"),
             Plan_Revision => Mappings (1).Plan_Revision)));
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Publications'Access, "publication read accepted an unrelated task contract");
      Improve.Storage.Close (Store);
   end;
   declare
      Path     : constant String := Root & "/publication.db";
      Store    : Improve.Storage.Store;
      Stored   : Improve.Model.Plan_Revision;
      Mappings : Improve.Storage.Publication_Vectors.Vector;
      Evidence : Improve.Storage.Verification_Vectors.Vector;

      procedure Read_Publications is
         Values : constant Improve.Storage.Publication_Vectors.Vector :=
           Improve.Storage.Publications (Store, "PLAN-000001");
      begin
         pragma Unreferenced (Values);
      end Read_Publications;
   begin
      Seed_One (Path, Store, Stored);
      History_Records (Stored, Mappings, Evidence);
      Improve.Storage.Record_Publications (Store, "PLAN-000001", Mappings);
      Improve.Storage.Close (Store);
      Replace_Row_Payload
        (Path, 10, 1,
         Improve.Persistence_Records.Encode_Publication
           ((Plan_Id       => To_Unbounded_String ("PLAN-999999"),
             Harness_Id    => Mappings (1).Harness_Task_Id,
             Origin        => Mappings (1).Origin,
             Contract      => Mappings (1).Contract,
             Plan_Revision => Mappings (1).Plan_Revision)));
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Publications'Access, "publication payload was not bound to its plan row context");
      Improve.Storage.Close (Store);
   end;
   declare
      Path     : constant String := Root & "/verification-revision.db";
      Store    : Improve.Storage.Store;
      Stored   : Improve.Model.Plan_Revision;
      Mappings : Improve.Storage.Publication_Vectors.Vector;
      Evidence : Improve.Storage.Verification_Vectors.Vector;

      procedure Read_Verifications is
         Values : constant Improve.Storage.Verification_Vectors.Vector :=
           Improve.Storage.Verifications (Store, "PLAN-000001");
      begin
         pragma Unreferenced (Values);
      end Read_Verifications;
   begin
      Seed_One (Path, Store, Stored);
      History_Records (Stored, Mappings, Evidence);
      Improve.Storage.Record_Verification (Store, "PLAN-000001", Evidence);
      Improve.Storage.Close (Store);
      Replace_Row_Payload
        (Path, 11, 1,
         Improve.Persistence_Records.Encode_Verification
           ((Plan_Id       => To_Unbounded_String ("PLAN-000001"),
             Assessment_Id => Evidence (1).Assessment_Id,
             Plan_Revision => Evidence (1).Plan_Revision + 1,
             Contract      => Evidence (1).Contract_Fingerprint,
             Scope         => Improve.Model.Task_Evaluation,
             Task_Id       => Evidence (1).Task_Id,
             Comparable    => Evidence (1).Comparable,
             Explanation   => Evidence (1).Explanation)));
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Verifications'Access, "verification read accepted an unknown plan revision");
      Improve.Storage.Close (Store);
   end;
   declare
      Path     : constant String := Root & "/verification.db";
      Store    : Improve.Storage.Store;
      Stored   : Improve.Model.Plan_Revision;
      Mappings : Improve.Storage.Publication_Vectors.Vector;
      Evidence : Improve.Storage.Verification_Vectors.Vector;

      procedure Read_Verifications is
         Values : constant Improve.Storage.Verification_Vectors.Vector :=
           Improve.Storage.Verifications (Store, "PLAN-000001");
      begin
         pragma Unreferenced (Values);
      end Read_Verifications;
   begin
      Seed_One (Path, Store, Stored);
      History_Records (Stored, Mappings, Evidence);
      Improve.Storage.Record_Verification (Store, "PLAN-000001", Evidence);
      Improve.Storage.Close (Store);
      Replace_Row_Payload
        (Path, 11, 1,
         Improve.Persistence_Records.Encode_Verification
           ((Plan_Id       => To_Unbounded_String ("PLAN-999999"),
             Assessment_Id => Evidence (1).Assessment_Id,
             Plan_Revision => Evidence (1).Plan_Revision,
             Contract      => Evidence (1).Contract_Fingerprint,
             Scope         => Improve.Model.Task_Evaluation,
             Task_Id       => Evidence (1).Task_Id,
             Comparable    => Evidence (1).Comparable,
             Explanation   => Evidence (1).Explanation)));
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Verifications'Access, "verification payload was not bound to its plan row context");
      Improve.Storage.Close (Store);
   end;
   declare
      Path      : constant String := Root & "/operation.db";
      Store     : Improve.Storage.Store;
      Stored    : Improve.Model.Plan_Revision;
      Task_Ids  : Improve.Model.UString_Vectors.Vector;
      Operation : Positive;

      procedure Read_Pending is
         Values : constant Improve.Storage.Operation_Vectors.Vector :=
           Improve.Storage.Pending_Publications (Store);
      begin
         pragma Unreferenced (Values);
      end Read_Pending;
   begin
      Seed_One (Path, Store, Stored);
      Task_Ids.Append (Stored.Tasks.First_Element.Id);
      Operation := Improve.Storage.Begin_Publication
        (Store, Stored, "remediation", Task_Ids);
      Improve.Storage.Complete_Publication (Store, Operation);
      Improve.Storage.Close (Store);
      Replace_Row_Payload (Path, 12, Operation + 1, "corrupt completion payload");
      Improve.Storage.Open (Store, Path, Writable => False);
      Expect_Data_Error
        (Read_Pending'Access, "mismatched completion payload hid a pending publication");
      Improve.Storage.Close (Store);
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Corrupt_Persistence_Context;
