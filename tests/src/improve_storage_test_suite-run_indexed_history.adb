separate (Improve_Storage_Test_Suite)
procedure Run_Indexed_History is
   Root        : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-history");
   Path        : constant String := Root & "/state.db";
   Store       : Improve.Storage.Store;
   Plan        : Improve.Model.Plan_Revision := Fixture (Root);
   Stored      : Improve.Model.Plan_Revision;
   Mappings    : Improve.Storage.Publication_Vectors.Vector;
   Evidence    : Improve.Storage.Verification_Vectors.Vector;
   Rejected    : Boolean := False;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
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
           Improve.Storage.Begin_Publication (Store, Stored, Task_Ids, Limits);
         begin
            pragma Unreferenced (Operation);
         end;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, "publication journal ignored its configured task limit");
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
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Indexed_History;
