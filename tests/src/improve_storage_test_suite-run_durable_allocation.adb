separate (Improve_Storage_Test_Suite)
procedure Run_Durable_Allocation is
   Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-allocation");
   Path   : constant String := Root & "/state.db";
   First  : Improve.Storage.Store;
   Second : Improve.Storage.Store;
   Plan   : Improve.Model.Plan_Revision := Fixture (Root);
   Locked : Boolean := False;
   Approval_Checked : Boolean := False;
   Journal_Checked  : Boolean := False;
   Rolled_Back       : Boolean := False;

   procedure Save_Revision (Handle : in out Improve.Storage.Store; Label : String; Revision : Positive) is
   begin
      Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest (Label));
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Handle, Plan);
      begin
         Assert
           (not Saved.Existing and then Saved.Plan.Revision = Revision,
            "interleaved writers did not allocate a unique plan revision");
      end;
   end Save_Revision;
begin
   Plan.Plan_Id := To_Unbounded_String ("PLAN-000001");
   begin
      Improve.Storage.Approve (First, "PLAN-000001", 1);
   exception
      when Error : Improve.Data_Error =>
         Approval_Checked := Ada.Exceptions.Exception_Message (Error) =
           "Improve state is not open for plan approval";
   end;
   declare Task_Ids : Improve.Model.UString_Vectors.Vector; begin
      Task_Ids.Append (To_Unbounded_String ("IMP-000001"));
      begin
         declare
            Operation : constant Positive :=
              Improve.Storage.Begin_Publication (First, Plan, "remediation", Task_Ids);
         begin
            pragma Unreferenced (Operation);
         end;
      exception
         when Error : Improve.Data_Error =>
            Journal_Checked := Ada.Exceptions.Exception_Message (Error) =
              "Improve state is not open for publication journaling";
      end;
   end;
   Assert
     (Approval_Checked and then Journal_Checked,
      "storage write preconditions were evaluated after database access");
   Improve.Storage.Open (First, Path, Writable => True);
   begin
      Improve.Storage.Open (Second, Path, Writable => True);
   exception
      when Improve.Dependency_Error => Locked := True;
   end;
   Assert (Locked, "a second writable handle bypassed the database lock");
   Save_Revision (First, "writer one revision one", 1);
   Improve.Storage.Close (First);
   declare
      Before : constant String := Identity_Counter_State (Path);
      Limits : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
   begin
      Improve.Storage.Open (First, Path, Writable => True);
      Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("rolled back revision"));
      Limits.Maximum_Total_Bytes := 128;
      begin
         declare
            Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (First, Plan, Limits);
         begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Improve.Data_Error => Rolled_Back := True;
      end;
      Improve.Storage.Close (First);
      Assert
        (Identity_Counter_State (Path) = Before,
         "failed allocation transaction changed a durable identity counter");
   end;
   Assert (Rolled_Back, "failed allocation transaction did not reject its byte budget");
   Improve.Storage.Open (Second, Path, Writable => True);
   Save_Revision (Second, "writer two revision two", 2);
   Improve.Storage.Close (Second);
   Improve.Storage.Open (First, Path, Writable => True);
   Save_Revision (First, "writer one revision three", 3);
   Improve.Storage.Close (First);
   declare
      Empty_Plan : Improve.Model.Plan_Revision := Fixture (Root);
      Before     : Unbounded_String;
   begin
      Empty_Plan.Findings.Clear;
      Empty_Plan.Tasks.Clear;
      Empty_Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("empty plan"));
      Before := To_Unbounded_String (Task_Identity_Counter_Value (Path));
      Improve.Storage.Open (First, Path, Writable => True);
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (First, Empty_Plan);
      begin
         Assert
           (Saved.Plan.Revision = 4 and then Saved.Plan.Tasks.Is_Empty,
            "empty plan persistence unexpectedly created a task or revision");
      end;
      Improve.Storage.Close (First);
      Assert
        (Task_Identity_Counter_Value (Path) = To_String (Before),
         "empty plan persistence consumed a task identity");
   end;
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Second);
      Improve.Storage.Close (First);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Durable_Allocation;
