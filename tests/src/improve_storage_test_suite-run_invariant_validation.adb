separate (Improve_Storage_Test_Suite)
procedure Run_Invariant_Validation is
   Root  : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-invariants");
   Path  : constant String := Root & "/state.db";
   Store : Improve.Storage.Store;
   Plan  : constant Improve.Model.Plan_Revision := Fixture (Root);

   procedure Reject (Value : Improve.Model.Plan_Revision; Context : String) is
      Rejected : Boolean := False;
   begin
      begin
         declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Value); begin
            pragma Unreferenced (Saved);
         end;
      exception
         when Improve.Data_Error => Rejected := True;
      end;
      Assert (Rejected, Context);
   end Reject;
begin
   Improve.Storage.Open (Store, Path, Writable => True);
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Tasks (2).Dependencies.Append (Invalid.Tasks (1).Id);
      Invalid.Tasks (2).Dependencies.Append (Invalid.Tasks (1).Id);
      Reject (Invalid, "storage accepted duplicate dependency edges");
   end;
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Tasks (1).Finding_Keys.Append (To_Unbounded_String ("unknown-finding"));
      Reject (Invalid, "storage accepted an unknown finding link");
   end;
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Baseline.Project_Id := 2;
      Reject (Invalid, "storage accepted a foreign baseline");
   end;
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Findings.Append
        (Improve.Model.Finding_Reference'
           (Project_Id  => 2,
            Run_Id      => Invalid.Baseline.Run_Id,
            Fingerprint => To_Unbounded_String ("foreign-finding"),
            others      => <>));
      Invalid.Tasks (1).Finding_Keys.Append (To_Unbounded_String ("foreign-finding"));
      Reject (Invalid, "storage accepted a foreign finding");
   end;
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Tasks (1).Relevant_Files.Append
        (To_Unbounded_String ("src/unsafe" & Character'Val (10) & "instruction.adb"));
      Reject (Invalid, "storage accepted a control character in a task path");
   end;
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Tasks (1).Relevant_Files.Append (To_Unbounded_String ("src/./unit.adb"));
      Reject (Invalid, "storage accepted a non-normalized task path");
   end;
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Invariant_Validation;
