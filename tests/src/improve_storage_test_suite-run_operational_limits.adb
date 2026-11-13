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
         Operation := Improve.Storage.Begin_Publication (Store, Saved.Plan, Task_Ids, Limits);
         Improve.Storage.Complete_Publication (Store, Operation);
         Assert
           (Improve.Storage.Pending_Publications (Store, Limits => Limits).Is_Empty,
            "publication journaling lost its configured limits");
      end;
   end;
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Operational_Limits;
