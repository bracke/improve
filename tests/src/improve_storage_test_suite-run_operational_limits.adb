separate (Improve_Storage_Test_Suite)
procedure Run_Operational_Limits is
   Root       : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-limits");
   Path       : constant String := Root & "/state.db";
   Store      : Improve.Storage.Store;
   Plan       : Improve.Model.Plan_Revision := Fixture (Root);
   Stored     : Improve.Model.Plan_Revision;
   Large_Text : Unbounded_String;
   Limits     : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
   Rejected   : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   Seed (Store, Plan, 1, Stored);
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
         "approval lost its configured read limits");
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
      end;
   end;
   declare
      Large_Plan : Improve.Model.Plan_Revision := Plan;
      Saved      : Improve.Storage.Save_Result;
      Mappings   : Improve.Storage.Publication_Vectors.Vector;
      Evidence   : Improve.Storage.Verification_Vectors.Vector;
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
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Operational_Limits;
