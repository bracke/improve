separate (Improve_Storage_Test_Suite)
procedure Run_Indexed_History is
   Root        : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-history");
   Path        : constant String := Root & "/state.db";
   Store       : Improve.Storage.Store;
   Store_Id    : Unbounded_String;
   Plan        : Improve.Model.Plan_Revision := Fixture (Root);
   Stored      : Improve.Model.Plan_Revision;
   Mappings    : Improve.Storage.Publication_Vectors.Vector;
   Evidence    : Improve.Storage.Verification_Vectors.Vector;
   Rejected    : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Store_Id := To_Unbounded_String (Improve.Storage.Identity (Store));
   Assert (Length (Store_Id) > 0, "state store has no persistent identity");
   Seed (Store, Plan, 4, Stored);
   declare Summaries : constant Improve.Storage.Summary_Vectors.Vector :=
     Improve.Storage.List (Store, Plan.Project);
   begin
      Assert
        (Summaries.Length = 1 and then Summaries.First_Element.Revision = 4 and then
         Summaries.First_Element.Task_Count = 5,
         "indexed listing did not select the latest complete revision");
   end;
   declare
      Task_Ids : Improve.Model.UString_Vectors.Vector;
      Limits   : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
   begin
      Task_Ids.Append (Stored.Tasks (1).Id);
      Task_Ids.Append (Stored.Tasks (2).Id);
      Limits.Maximum_Tasks := 1;
      begin
         declare Operation : constant Positive :=
           Improve.Storage.Begin_Publication (Store, Stored, "remediation", Task_Ids, Limits);
         begin
            pragma Unreferenced (Operation);
         end;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "publication journal ignored its configured task limit");
   end;
   declare
      Limits : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;

      procedure Expect_History_Rejection
        (Action : not null access procedure;
         Message : String) is
      begin
         Rejected := False;
         begin
            Action.all;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, Message);
      end Expect_History_Rejection;

      procedure Load_Latest is
         Value : constant Improve.Model.Plan_Revision :=
           Improve.Storage.Load (Store, "PLAN-000001", Limits);
      begin
         pragma Unreferenced (Value);
      end Load_Latest;

      procedure List_Plans is
         Values : constant Improve.Storage.Summary_Vectors.Vector :=
           Improve.Storage.List (Store, Plan.Project, Limits => Limits);
      begin
         pragma Unreferenced (Values);
      end List_Plans;

      procedure Load_Historical_Task is
         Value : constant Improve.Model.Plan_Revision :=
           Improve.Storage.Load_Task
             (Store, To_String (Stored.Tasks.First_Element.Id), Limits => Limits);
      begin
         pragma Unreferenced (Value);
      end Load_Historical_Task;

      procedure Save_Next_Revision is
         Candidate : Improve.Model.Plan_Revision := Plan;
      begin
         Candidate.Fingerprint := To_Unbounded_String
           (Improve.Stable_Digest ("bounded fifth revision"));
         declare
            Value : constant Improve.Storage.Save_Result :=
              Improve.Storage.Save (Store, Candidate, Limits);
         begin
            pragma Unreferenced (Value);
         end;
      end Save_Next_Revision;
   begin
      Limits.Maximum_History := 3;
      Expect_History_Rejection
        (Load_Latest'Access, "latest-plan lookup ignored its configured history limit");
      Expect_History_Rejection
        (List_Plans'Access, "plan listing ignored its configured history limit");
      Expect_History_Rejection
        (Load_Historical_Task'Access, "task lookup ignored its configured history limit");
      Expect_History_Rejection
        (Save_Next_Revision'Access, "plan persistence ignored its configured history limit");
   end;
   Rejected := False;
   begin
      declare Value : constant Improve.Model.Plan_Revision :=
        Improve.Storage.Load
          (Store, "PLAN-000001",
           (Maximum_Findings     => 10,
            Maximum_Tasks        => 1,
            Maximum_Task_Details => 10,
            Maximum_Task_Links   => 10,
            Maximum_History      => 10,
            Maximum_Text_Bytes   => 1_024));
      begin
         pragma Unreferenced (Value);
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "plan reconstruction ignored its configured task limit");
   declare
      Task_Ids  : Improve.Model.UString_Vectors.Vector;
      Operation : Positive;
      Candidate : Improve.Model.Plan_Revision := Plan;
      Limits    : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
   begin
      Task_Ids.Append (Stored.Tasks.First_Element.Id);
      Operation := Improve.Storage.Begin_Publication (Store, Stored, "remediation", Task_Ids);
      Candidate.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("revision saved after publication start"));
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Candidate);
      begin
         pragma Unreferenced (Saved);
      end;
      Limits.Maximum_History := 1;
      Assert
        (Improve.Storage.Pending_Publications (Store, Limits => Limits).Length = 1,
         "plan revision history contaminated the publication journal namespace");
      Improve.Storage.Complete_Publication (Store, Operation, Limits);
   end;
   History_Records (Stored, Mappings, Evidence);
   Improve.Storage.Record_Publications (Store, To_String (Stored.Plan_Id), Mappings);
   Improve.Storage.Record_Verification (Store, To_String (Stored.Plan_Id), Evidence);
   declare
      Invalid_Mapping  : Improve.Storage.Publication_Vectors.Vector := Mappings;
      Invalid_Evidence : Improve.Storage.Verification_Vectors.Vector := Evidence;
   begin
      Invalid_Mapping (1).Contract := To_Unbounded_String ("unrelated-contract");
      Rejected := False;
      begin
         Improve.Storage.Record_Publications (Store, To_String (Stored.Plan_Id), Invalid_Mapping);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "storage accepted an unrelated publication contract");
      Invalid_Evidence (1).Task_Id := To_Unbounded_String ("IMP-UNKNOWN");
      Rejected := False;
      begin
         Improve.Storage.Record_Verification (Store, To_String (Stored.Plan_Id), Invalid_Evidence);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "storage accepted verification for an unknown task");
   end;
   Assert
     (Improve.Storage.Publications (Store, To_String (Stored.Plan_Id)).Length = 2 and then
      Improve.Storage.Verifications (Store, To_String (Stored.Plan_Id)).Length = 2,
      "history records were not plan-scoped");
   declare
      Snapshot : constant Improve.Storage.Inspection_History :=
        Improve.Storage.History (Store, To_String (Stored.Plan_Id));
      Historical : constant Improve.Storage.Inspection_History :=
        Improve.Storage.History (Store, To_String (Stored.Plan_Id), Stored.Revision);
   begin
      Assert
        (Snapshot.Selected_Revision = 5 and then Historical.Selected_Revision = Stored.Revision and then
         Snapshot.Publications.Length = 2 and then Snapshot.Verifications.Length = 2,
         "joined inspection history omitted persisted records");
   end;
   Rejected := False;
   begin
      declare Values : constant Improve.Storage.Publication_Vectors.Vector :=
        Improve.Storage.Publications (Store, To_String (Stored.Plan_Id), Maximum => 1);
      begin
         pragma Unreferenced (Values);
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "publication query ignored its materialization limit");
   Improve.Storage.Close (Store);
   declare Moved : constant String := Root & "/moved-state.db"; begin
      Ada.Directories.Rename (Path, Moved);
      Improve.Storage.Open (Store, Moved, Writable => False);
      Assert
        (Improve.Storage.Identity (Store) = To_String (Store_Id),
         "moving the state database changed its persistent identity");
      Improve.Storage.Close (Store);
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Indexed_History;
