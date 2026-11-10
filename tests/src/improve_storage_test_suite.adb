with Ada.Directories;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.Model;
with Improve.Storage;
with Project_Tools.Files;

package body Improve_Storage_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Ada.Containers.Count_Type;

   type Storage_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Storage_Case;

   overriding function Name (Item : Storage_Case) return AUnit.Message_String is
     (AUnit.Format ("IMP_STORAGE_INDEXED_HISTORY"));

   overriding procedure Run_Test (Item : in out Storage_Case) is
      pragma Unreferenced (Item);
      Root  : constant String := "/tmp/improve_storage_indexed_history";
      Path  : constant String := Root & "/state.db";
      Store : Improve.Storage.Store;
      Plan  : Improve.Model.Plan_Revision;

      function Image (Value : Positive) return String is
        (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));
   begin
      Project_Tools.Files.Delete_Tree (Root);
      Ada.Directories.Create_Directory (Root);
      Plan.Project :=
        (Id          => 1,
         Name        => To_Unbounded_String ("scale"),
         Path        => To_Unbounded_String (Root),
         Database_Id => To_Unbounded_String (Root & "/quality.db"));
      Plan.Baseline :=
        (Project_Id   => 1,
         Run_Id       => 1,
         Source_Id    => To_Unbounded_String ("source"),
         Policy_Id    => To_Unbounded_String ("policy"),
         Toolchain_Id => To_Unbounded_String ("toolchain"),
         Snapshot_Id  => To_Unbounded_String ("snapshot"));
      Plan.Working_Source_Id := To_Unbounded_String ("working");
      Plan.Planner_Id := To_Unbounded_String ("planner");
      Plan.Review_Status := To_Unbounded_String ("not-required");
      for Index in 1 .. 5 loop
         Plan.Tasks.Append
           (Improve.Model.Task_Specification'
              (Id              => To_Unbounded_String ("DRAFT-" & Image (Index)),
               Title           => To_Unbounded_String ("Indexed task " & Image (Index)),
               Category        => To_Unbounded_String ("remediation"),
               Goal            => To_Unbounded_String ("Exercise indexed revision persistence"),
               Problem         => To_Unbounded_String ("Historical task lookup must remain bounded"),
               Evidence        => To_Unbounded_String ("storage scale fixture"),
               Scope           => To_Unbounded_String ("task " & Image (Index)),
               Out_Of_Scope    => To_Unbounded_String ("unrelated tasks"),
               Requirements    => To_Unbounded_String ("none"),
               Acceptance      => To_Unbounded_String ("indexed persistence succeeds"),
               Verification    => To_Unbounded_String ("load the stored revision"),
               Requires_Review => False,
               others          => <>));
      end loop;
      Improve.Storage.Open (Store, Path, Writable => True);
      for Revision in 1 .. 4 loop
         Plan.Fingerprint := To_Unbounded_String (Improve.Stable_Digest ("scale revision " & Image (Revision)));
         declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Plan); begin
            Assert
              (not Saved.Existing and then Saved.Plan.Revision = Revision,
               "indexed scale history did not create the expected revision");
         end;
      end loop;
      declare Summaries : constant Improve.Storage.Summary_Vectors.Vector := Improve.Storage.List (Store, Plan.Project);
      begin
         Assert
           (Summaries.Length = 1 and then Summaries.First_Element.Revision = 4 and then
            Summaries.First_Element.Task_Count = 5,
            "indexed plan listing did not select the latest large revision");
      end;
      Improve.Storage.Close (Store);
      Project_Tools.Files.Delete_Tree (Root);
   exception
      when others =>
         Improve.Storage.Close (Store);
         Project_Tools.Files.Delete_Tree (Root);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Storage_Case));
      return Result;
   end Suite;
end Improve_Storage_Test_Suite;
