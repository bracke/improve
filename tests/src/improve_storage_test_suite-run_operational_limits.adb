separate (Improve_Storage_Test_Suite)
procedure Run_Operational_Limits is
   Root       : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-limits");
   Path       : constant String := Root & "/state.db";
   Store      : Improve.Storage.Store;
   Plan       : Improve.Model.Plan_Revision := Fixture (Root);
   Stored     : Improve.Model.Plan_Revision;
   Large_Text : Unbounded_String;
   Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
   Rejected   : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
   Limits.Maximum_Total_Bytes := 128;
   begin
      Stored := Improve.Storage.Load (Store, "PLAN-000001", Limits);
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "plan reconstruction ignored its aggregate persisted-byte limit");
   Rejected := False;
   declare
      Aggregate_Plan : Improve.Model.Plan_Revision := Plan;
   begin
      Aggregate_Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("aggregate write limit"));
      begin
         declare
            Saved : constant Improve.Storage.Save_Result :=
              Improve.Storage.Save (Store, Aggregate_Plan, Limits);
         begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "plan persistence ignored its aggregate persisted-byte limit");
   end;
   Rejected := False;
   declare
      Prior        : Improve.Model.Plan_Revision := Plan;
      Current      : Improve.Model.Plan_Revision := Plan;
      Prior_Limits : constant Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Read_Bound   : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
   begin
      for Index in 1 .. Natural (Prior.Tasks.Length) loop
         Prior.Tasks (Index).Goal := To_Unbounded_String ([1 .. 512 => 'p']);
      end loop;
      Prior.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("large previous revision"));
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Prior, Prior_Limits);
      begin
         pragma Unreferenced (Saved);
      end;
      Current.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("bounded previous revision read"));
      Read_Bound.Maximum_Total_Bytes := 2_000;
      begin
         declare
            Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Current, Read_Bound);
         begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Error : Improve.Data_Error =>
            Rejected := Ada.Exceptions.Exception_Message (Error) =
              "plan read exceeds configured aggregate persisted-byte limit";
      end;
      Assert (Rejected, "plan persistence ignored aggregate bytes read from its previous revision");
   end;
   Rejected := False;
   Limits.Maximum_Total_Bytes := Improve.Storage.Default_Persistence_Limits.Maximum_Total_Bytes;
   Append (Large_Text, [1 .. 384 => 'x']);
   Plan.Tasks (1).Goal := Large_Text;
   Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("large approved revision"));
   Limits.Maximum_Text_Bytes := 128;
   begin
      declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan, Limits); begin
         pragma Unreferenced (Saved);
      end;
   exception
      when Improve.Data_Error => Rejected := True;
   end;
   Assert (Rejected, "plan persistence ignored its configured text limit");
   declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan); begin
      Rejected := False;
      begin
         Improve.Storage.Approve (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "approval ignored its configured payload limit");
      Limits.Maximum_Text_Bytes := 1_024;
      Improve.Storage.Approve (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits);
      Assert
        (Improve.Storage.Is_Approved
           (Store, To_String (Saved.Plan.Plan_Id), Saved.Plan.Revision, Limits),
         "approval lost its configured persistence limits");
      declare
         Task_Ids : Improve.Model.UString_Vectors.Vector;
         Operation : Positive;
      begin
         Task_Ids.Append (Saved.Plan.Tasks.First_Element.Id);
         Limits.Maximum_Text_Bytes := 512;
         Rejected := False;
         begin
            Operation := Improve.Storage.Begin_Publication
              (Store, Saved.Plan, [1 .. 400 => 'k'], Task_Ids, Limits);
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "publication journal accepted an oversized complete payload");
         Limits.Maximum_Text_Bytes := 1_024;
         Operation := Improve.Storage.Begin_Publication
           (Store, Saved.Plan, "remediation", Task_Ids, Limits);
         Improve.Storage.Complete_Publication (Store, Operation);
         Assert
           (Improve.Storage.Pending_Publications (Store, Limits => Limits).Is_Empty,
            "publication journaling lost its configured limits");
         Limits.Maximum_History := 1;
         Rejected := False;
         begin
            declare
               Pending : constant Improve.State.Publication_Operation_Vectors.Vector :=
                 Improve.Storage.Pending_Publications (Store, Limits => Limits);
               pragma Unreferenced (Pending);
            begin
               null;
            end;
         exception
            when Improve.Data_Error => Rejected := True;
         end;
         Assert (Rejected, "publication journal scan exceeded its configured history limit");
         Limits.Maximum_History := Improve.Storage.Default_Persistence_Limits.Maximum_History;
      end;
   end;
   declare
      Large_Plan : Improve.Model.Plan_Revision := Plan;
      Saved      : Improve.Storage.Save_Result;
      Mappings   : Improve.State.Publication_Vectors.Vector;
      Evidence   : Improve.State.Verification_Vectors.Vector;
   begin
      Large_Plan.Tasks (1).Goal := To_Unbounded_String ([1 .. 600 => 'g']);
      Large_Plan.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("large contract recording"));
      Limits.Maximum_Text_Bytes := 1_024;
      Limits.Maximum_History := 10;
      Saved := Improve.Storage.Save (Store, Large_Plan, Limits);
      History_Records (Saved.Plan, Mappings, Evidence);
      Limits.Maximum_Text_Bytes := 512;
      Rejected := False;
      begin
         Improve.Storage.Record_Publications
           (Store, To_String (Saved.Plan.Plan_Id), Mappings, Limits);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "publication recording ignored its configured contract limit");
      Limits.Maximum_Text_Bytes := 1_024;
      Improve.Storage.Record_Publications
        (Store, To_String (Saved.Plan.Plan_Id), Mappings, Limits);
      Improve.Storage.Record_Verification
        (Store, To_String (Saved.Plan.Plan_Id), Evidence, Limits);
      Assert
        (Improve.Storage.Publications
           (Store, To_String (Saved.Plan.Plan_Id), Limits => Limits).Length >= 2,
         "publication recording reloaded a valid large contract with default limits");
      Limits.Maximum_History := 1;
      Rejected := False;
      begin
         Improve.Storage.Record_Publications
           (Store, To_String (Saved.Plan.Plan_Id), Mappings, Limits);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "publication recording ignored its configured history limit");
   end;
   Improve.Storage.Close (Store);
   declare
      Budget_Path   : constant String := Root & "/history-budget.db";
      Budget_Store  : Improve.Storage.Store;
      Budget_Plan   : Improve.Model.Plan_Revision := Fixture (Root);
      Budget_Stored : Improve.Model.Plan_Revision;
      Budget_Limits : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Task_Ids      : Improve.Model.UString_Vectors.Vector;
      Operation     : Positive := 1;

      procedure Expect_Limit (Action : not null access procedure; Message : String) is
         Was_Rejected : Boolean := False;
      begin
         begin
            Action.all;
         exception
            when Improve.Data_Error => Was_Rejected := True;
         end;
         Assert (Was_Rejected, Message);
      end Expect_Limit;

      procedure Approve_With_Tight_Budget is
      begin
         Improve.Storage.Approve
           (Budget_Store, To_String (Budget_Stored.Plan_Id), Budget_Stored.Revision, Budget_Limits);
      end Approve_With_Tight_Budget;

      procedure Read_Approval_With_Tight_Budget is
         Approved : constant Boolean :=
           Improve.Storage.Is_Approved
             (Budget_Store, To_String (Budget_Stored.Plan_Id), Budget_Stored.Revision, Budget_Limits);
      begin
         pragma Unreferenced (Approved);
      end Read_Approval_With_Tight_Budget;

      procedure Begin_With_Tight_Budget is
         Started : constant Positive :=
           Improve.Storage.Begin_Publication
             (Budget_Store, Budget_Stored, "remediation", Task_Ids, Budget_Limits);
      begin
         pragma Unreferenced (Started);
      end Begin_With_Tight_Budget;

      procedure Save_With_Tight_Budget is
         Candidate : Improve.Model.Plan_Revision := Budget_Plan;
         Saved     : Improve.Storage.Save_Result;
      begin
         Candidate.Fingerprint := To_Unbounded_String
           (Improve.Stable_Digest ("operation-wide save budget"));
         Saved := Improve.Storage.Save (Budget_Store, Candidate, Budget_Limits);
         pragma Unreferenced (Saved);
      end Save_With_Tight_Budget;

      procedure Complete_With_Tight_Budget is
      begin
         Improve.Storage.Complete_Publication (Budget_Store, Operation, Budget_Limits);
      end Complete_With_Tight_Budget;
   begin
      Improve.Storage.Open (Budget_Store, Budget_Path, Writable => True);
      Seed (Budget_Store, Budget_Plan, 1, Budget_Stored);
      Task_Ids.Append (Budget_Stored.Tasks.First_Element.Id);
      Budget_Limits.Maximum_History := 1;
      Expect_Limit
        (Approve_With_Tight_Budget'Access,
         "approval reset its operation-wide history budget after loading the plan");
      Improve.Storage.Approve
        (Budget_Store, To_String (Budget_Stored.Plan_Id), Budget_Stored.Revision);
      Expect_Limit
        (Read_Approval_With_Tight_Budget'Access,
         "approval lookup reset its operation-wide history budget after loading the plan");
      Expect_Limit
        (Begin_With_Tight_Budget'Access,
         "publication start reset its operation-wide history budget after loading the plan");
      Expect_Limit
        (Save_With_Tight_Budget'Access,
         "plan save did not charge its appended revision to the operation-wide history budget");
      Operation := Improve.Storage.Begin_Publication
        (Budget_Store, Budget_Stored, "remediation", Task_Ids);
      Expect_Limit
        (Complete_With_Tight_Budget'Access,
         "publication completion did not charge its started operation read to the history budget");
      Improve.Storage.Complete_Publication (Budget_Store, Operation);
      Improve.Storage.Close (Budget_Store);
   end;
   declare
      Summary_Path   : constant String := Root & "/summary.db";
      Summary_Store  : Improve.Storage.Store;
      Summary_Plan   : Improve.Model.Plan_Revision := Fixture (Root);
      Summary_Stored : Improve.Model.Plan_Revision;
      Summary_Limits : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;

      procedure Read_Summaries is
         Values : constant Improve.State.Summary_Vectors.Vector :=
           Improve.Storage.List_All (Summary_Store, Limits => Summary_Limits);
      begin
         pragma Unreferenced (Values);
      end Read_Summaries;
   begin
      Improve.Storage.Open (Summary_Store, Summary_Path, Writable => True);
      Seed (Summary_Store, Summary_Plan, 1, Summary_Stored);
      Improve.Storage.Close (Summary_Store);
      Summary_Limits.Maximum_Total_Bytes := Summary_Row_Bytes (Summary_Path, 1) - 1;
      Improve.Storage.Open (Summary_Store, Summary_Path, Writable => False);
      Rejected := False;
      begin
         Read_Summaries;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "plan summary ignored its aggregate persisted-byte limit");
      Improve.Storage.Close (Summary_Store);
   end;
   declare
      Foreign_Path  : constant String := Root & "/foreign.db";
      Foreign_Store : Improve.Storage.Store;
   begin
      Create_Foreign_Database (Foreign_Path);
      Rejected := False;
      begin
         Improve.Storage.Open (Foreign_Store, Foreign_Path, Writable => True);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert
        (Rejected and then not Has_Improve_Table (Foreign_Path),
         "writable open modified a database without Improve ownership metadata");
   end;
   declare
      Ownership_Path  : constant String := Root & "/ownership.db";
      Ownership_Store : Improve.Storage.Store;
   begin
      Improve.Storage.Open (Ownership_Store, Ownership_Path, Writable => True);
      Improve.Storage.Close (Ownership_Store);
      Corrupt_Schema_Ownership (Ownership_Path);
      Rejected := False;
      begin
         Improve.Storage.Open (Ownership_Store, Ownership_Path, Writable => True);
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "writable open accepted invalid Improve ownership metadata");
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Operational_Limits;
