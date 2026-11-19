with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Files;

package body Improve_CI_Checks is
   procedure Require (Path, Fragment : String) is
   begin
      if not Project_Tools.Files.File_Contains (Path, Fragment) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "CI contract is missing from " & Path & ": " & Fragment);
         raise Program_Error with "incomplete CI contract";
      end if;
   end Require;

   procedure Validate_Action_Pins is
   begin
      for Path_Value of Project_Tools.Files.List_Tree (".github", "*.yml") loop
         declare
            Path  : constant String := Ada.Strings.Unbounded.To_String (Path_Value);
            Text  : constant String := Project_Tools.Files.Read_Raw_File (Path);
            Start : Natural := Text'First;
         begin
            while Start <= Text'Last loop
               declare
                  Stop : Natural := Start;
               begin
                  while Stop <= Text'Last and then Text (Stop) /= ASCII.LF loop
                     Stop := Stop + 1;
                  end loop;
                  declare
                     Line : constant String := Text (Start .. Stop - 1);
                     Uses : constant Natural := Ada.Strings.Fixed.Index (Line, "uses:");
                     At_Sign : constant Natural := Ada.Strings.Fixed.Index (Line, "@");
                  begin
                     if Uses > 0 and then Ada.Strings.Fixed.Index (Line, "uses: ./") = 0 and then
                       (At_Sign = 0 or else Line'Last - At_Sign < 40 or else
                        (for some Index in At_Sign + 1 .. At_Sign + 40 =>
                           Line (Index) not in '0' .. '9' | 'a' .. 'f'))
                     then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error, "GitHub Action is not commit-pinned: " & Path & ": " & Line);
                        raise Program_Error with "floating GitHub Action reference";
                     end if;
                  end;
                  Start := Stop + 1;
               end;
            end loop;
         end;
      end loop;
   end Validate_Action_Pins;

   procedure Validate_Workflow_Contracts is
      type Manifest_List is array (Positive range <>) of Ada.Strings.Unbounded.Unbounded_String;
      Manifests : constant Manifest_List :=
        [Ada.Strings.Unbounded.To_Unbounded_String ("alire.toml"),
         Ada.Strings.Unbounded.To_Unbounded_String ("alire.release.toml"),
         Ada.Strings.Unbounded.To_Unbounded_String ("tests/alire.toml"),
         Ada.Strings.Unbounded.To_Unbounded_String ("tests/alire.release.toml"),
         Ada.Strings.Unbounded.To_Unbounded_String ("model_runner_runtime/alire.toml"),
         Ada.Strings.Unbounded.To_Unbounded_String ("model_runner_runtime/alire.release.toml")];
   begin
      for Manifest of Manifests loop
         Require (Ada.Strings.Unbounded.To_String (Manifest), "[available.'case(os)']");
         Require (Ada.Strings.Unbounded.To_String (Manifest), "'linux|macos' = true");
         Require (Ada.Strings.Unbounded.To_String (Manifest), "'...' = false");
      end loop;
      Require ("model_runner_runtime/improve_model_runner_runtime.gpr", "with ""model_runner_inference.gpr"";");
      Require (".github/workflows/ci.yml", "dependency-preflight:");
      Require (".github/workflows/ci.yml", "clean-room-build:");
      Require (".github/workflows/ci.yml", "phase0/bin/contract_probe");
      Require (".github/workflows/ci.yml", "macos-15-intel");
      Require (".github/workflows/ci.yml", "cache-build-artifacts: ""false""");
      Require (".github/actions/setup-workspace/action.yml", "gnatdoc_bin=26.0.0");
      Require (".github/actions/setup-workspace/action.yml", "gnatprove=15.1.0");
      Require (".github/workflows/ci.yml", "install-release-tools: ""true""");
      Require (".github/workflows/release.yml", "install-release-tools: ""true""");
      Require (".github/workflows/ci.yml", "RUNNER_TEMP/improve-ci-artifacts");
      Require (".github/workflows/ci.yml", "path: ${{ runner.temp }}/improve-ci-artifacts");
   end Validate_Workflow_Contracts;
end Improve_CI_Checks;
