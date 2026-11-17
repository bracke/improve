separate (Improve_Storage_Test_Suite)
procedure Run_Invariant_Validation is
   Root  : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-storage-invariants");
   Path  : constant String := Root & "/state.db";
   Store : Improve.Storage.Store;
   Plan  : Improve.Model.Plan_Revision := Fixture (Root);

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
   Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("invariant baseline"));
   Improve.Storage.Open (Store, Path, Writable => True);
   declare Invalid : Improve.Model.Plan_Revision := Plan; begin
      Invalid.Fingerprint := Null_Unbounded_String;
      Reject (Invalid, "storage accepted an empty plan fingerprint");
   end;
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
   declare
      First     : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan);
      Repeated  : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan);
      Collision : Improve.Model.Plan_Revision := Plan;
   begin
      Assert
        (not First.Existing and then Repeated.Existing,
         "storage did not preserve exact fingerprint idempotency");
      Collision.Tasks (1).Goal := To_Unbounded_String ("different semantic content");
      Reject (Collision, "storage accepted conflicting content under an existing plan fingerprint");
   end;
   declare
      Legacy   : Improve.Model.Plan_Revision := Plan;
      Valid    : Improve.Model.Plan_Revision;
      Original : constant Improve.Model.Finding_Reference :=
        (Project_Id       => Legacy.Project.Id,
         Run_Id           => Legacy.Baseline.Run_Id,
         Indicator        => Ada_Quality.Types.STR_01,
         Rule             => To_Unbounded_String ("manifest.same-fingerprint"),
         Fingerprint      => To_Unbounded_String ("shared-source-fingerprint"),
         Semantic_Subject => To_Unbounded_String ("manifest subject"),
         others           => <>);
      Second   : Improve.Model.Finding_Reference := Original;
      First    : Improve.Storage.Save_Result;
      Saved    : Improve.Storage.Save_Result;
   begin
      Second.Indicator := Ada_Quality.Types.BLD_01;
      Second.Rule := To_Unbounded_String ("build.same-fingerprint");
      Second.Semantic_Subject := To_Unbounded_String ("build subject");
      Legacy.Findings.Append (Original);
      Legacy.Tasks (Legacy.Tasks.First_Index).Finding_Keys.Append (Original.Fingerprint);
      Legacy.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("legacy raw finding link"));
      First := Improve.Storage.Save (Store, Legacy);
      Valid := Legacy;
      Valid.Tasks (Valid.Tasks.First_Index).Finding_Keys.Replace_Element
        (1, To_Unbounded_String (Improve.Model.Finding_Key (Original)));
      Valid.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("qualified finding link"));
      Saved := Improve.Storage.Save (Store, Valid);
      Assert
        (Saved.Plan.Tasks.First_Element.Id = First.Plan.Tasks.First_Element.Id,
         "canonical finding links broke logical identity continuity with legacy plans");
      Valid.Findings.Append (Second);
      Valid.Tasks (Valid.Tasks.First_Index).Finding_Keys.Append
        (To_Unbounded_String (Improve.Model.Finding_Key (Second)));
      Valid.Fingerprint := To_Unbounded_String
        (Improve.Stable_Digest ("qualified duplicate source fingerprints"));
      Saved := Improve.Storage.Save (Store, Valid);
      Assert
        (not Saved.Existing and then Saved.Plan.Findings.Length = 2,
         "storage collapsed distinct qualified findings sharing a source fingerprint");
   end;
   Improve.Storage.Close (Store);
   Duplicate_Row (Path, Table => 6, Source_Id => 1, New_Id => 99);
   Improve.Storage.Open (Store, Path, Writable => True);
   Reject (Plan, "storage accepted duplicate persisted plan fingerprints");
   Improve.Storage.Close (Store);
   Project_Tools.Files.Delete_Tree (Root);
exception
   when others =>
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
      raise;
end Run_Invariant_Validation;
