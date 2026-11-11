separate (Improve_Test_Suite)
procedure Run_Domain_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Catalog =>
            Assert (Improve.Text.Catalog_Is_Valid, "message catalog is invalid");
            declare
               Value : constant Improve.Text.Argument := Improve.Text.Arg ("name", "value");
               Rejected : Boolean := False;
            begin
               Assert (To_String (Value.Name) = "name" and then To_String (Value.Value) = "value",
                       "message argument construction failed");
               begin
                  declare Text : constant String := Improve.Text.Message ("missing.key"); begin
                     Assert (Text = "", "missing catalog message unexpectedly rendered");
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "missing catalog key was accepted");
               Improve.Presentation.Configure (Improve.Config.Terminal_Format, Improve.Config.Color_Always);
               Assert (Improve.Presentation.Header ("Improve") /= "", "styled header was empty");
               Improve.Presentation.Configure (Improve.Config.Terminal_Format, Improve.Config.Color_Never);
            end;
         when Digest =>
            Assert
              (Improve.Stable_Digest ("") =
                 "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" and then
               Improve.Stable_Digest ("improve") = Improve.Stable_Digest ("improve") and then
               Improve.Stable_Digest ("improve") /= Improve.Stable_Digest ("Improve"),
               "SHA-256 stable digest is incorrect or nondeterministic");
         when Project_Discovery =>
            declare
               Data       : constant Fixture := Build_Fixture ("projects");
               Store      : Improve.Source.Repository;
               Writer     : Ada_Quality.Storage.Store;
               Empty_Id   : Positive;
               Left_Id    : Positive;
               Right_Id   : Positive;
               Rejected   : Boolean := False;
               Left_Path  : constant String := To_String (Data.Directory) & "/left/shared";
               Right_Path : constant String := To_String (Data.Directory) & "/right/shared";
               Empty_Path : constant String := To_String (Data.Directory) & "/empty";

               procedure Initialize_Crate (Path, Name : String) is
               begin
                  Ada.Directories.Create_Path (Path);
                  Project_Tools.Files.Write_Text_File
                    (Path & "/alire.toml",
                     "name = """ & Name & """" & ASCII.LF &
                     "description = ""source selection fixture""" & ASCII.LF &
                     "version = ""0.1.0-dev""" & ASCII.LF &
                     "authors = [""Improve tests""]" & ASCII.LF &
                     "maintainers = [""Improve tests <tests@example.invalid>""]" & ASCII.LF &
                     "maintainers-logins = [""improve-tests""]" & ASCII.LF &
                     "licenses = ""MIT""" & ASCII.LF &
                     "tags = [""test""]" & ASCII.LF);
               end Initialize_Crate;
            begin
               Initialize_Crate (Left_Path, "left_shared");
               Initialize_Crate (Right_Path, "right_shared");
               Initialize_Crate (Empty_Path, "empty_project");
               Ada_Quality.Storage.Open (Writer, To_String (Data.Database));
               Empty_Id := Ada_Quality.Storage.Add_Project (Writer, Empty_Path);
               Left_Id := Ada_Quality.Storage.Add_Project (Writer, Left_Path);
               Right_Id := Ada_Quality.Storage.Add_Project (Writer, Right_Path);
               Assert (Left_Id /= Right_Id, "distinct project registrations reused an identity");
               Ada_Quality.Storage.Close (Writer);

               Improve.Source.Open (Store, To_String (Data.Database));
               Assert (Improve.Source.Projects (Store).Length = 4, "registered projects were not discovered");
               Assert (Improve.Source.Identity (Store)'Length = 24, "snapshot identity is malformed");
               Assert
                 (Improve.Source.Resolve_Project (Store, To_String (Data.Target)).Id = Data.Project,
                  "canonical project path did not resolve");
               Assert
                 (Improve.Source.Resolve_Project (Store, "project").Id = Data.Project,
                  "unique project name did not resolve");
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "shared");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "ambiguous project name was accepted");

               Rejected := False;
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "empty project selector was accepted");

               Rejected := False;
               begin
                  declare
                     Value : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "999999999999999999999999999999999999999999");
                     pragma Unreferenced (Value);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "out-of-range project identity was accepted");

               Rejected := False;
               begin
                  declare
                     Project : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, Id_Image (Empty_Id));
                  begin
                     Assert
                       (Improve.Source.Latest_Completed_Run (Store, Project) = 0,
                        "empty project reported a completed assessment");
                     declare
                        Value : constant Improve.Source.Selection :=
                          Improve.Source.Select_Assessment (Store, Project);
                        pragma Unreferenced (Value);
                     begin
                        null;
                     end;
                  end;
               exception
                  when Improve.Dependency_Error => Rejected := True;
               end;
               Assert (Rejected, "project without a completed assessment was accepted");

               Improve.Source.Open (Store, To_String (Data.Database));
               Improve.Source.Close (Store);
               Rejected := False;
               begin
                  declare
                     Values : constant Ada_Quality.Reporting.Project_Vectors.Vector := Improve.Source.Projects (Store);
                     pragma Unreferenced (Values);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "closed quality repository was readable");
               Remove (Data);
            end;
         when Latest_Completed =>
            declare
               Data  : constant Fixture := Build_Fixture ("latest");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Chosen : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
               begin
                  Assert (Chosen.Assessment.Run.Id = Data.Run, "newer interrupted run replaced completed baseline");
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Explicit_Incomplete_Rejected =>
            declare
               Data     : constant Fixture := Build_Fixture ("explicit");
               Store    : Improve.Source.Repository;
               Rejected : Boolean := False;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
               begin
                  begin
                     declare
                        Chosen : constant Improve.Source.Selection :=
                          Improve.Source.Select_Assessment (Store, Project, Data.Interrupted);
                        pragma Unreferenced (Chosen);
                     begin null; end;
                  exception
                     when Improve.Dependency_Error => Rejected := True;
                  end;
               end;
               Assert (Rejected, "explicit interrupted assessment was accepted");
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Normalize_Findings =>
            declare
               Data  : constant Fixture := Build_Fixture ("normalize");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Chosen : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Values : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Chosen);
               begin
                  Assert (Values.Length = 3, "findings were not deduplicated/classified into three candidates");
                  Assert (To_String (Values.First_Element.Fingerprint) = "fixture-manifest",
                          "Ada Quality finding fingerprint was not preserved");
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Unknown_Project_Rejected =>
            declare
               Data     : constant Fixture := Build_Fixture ("unknown_project");
               Store    : Improve.Source.Repository;
               Rejected : Boolean := False;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               begin
                  declare
                     Project : constant Improve.Model.Project_Reference :=
                       Improve.Source.Resolve_Project (Store, "not-registered");
                     pragma Unreferenced (Project);
                  begin
                     null;
                  end;
               exception
                  when Improve.Argument_Error => Rejected := True;
               end;
               Assert (Rejected, "unknown project was accepted");
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Safe_Path_Validation =>
            Assert (Improve.Findings.Safe_Relative_Path (""), "empty relative path was rejected");
            Assert (Improve.Findings.Safe_Relative_Path ("src/parser.adb"), "safe path was rejected");
            Assert (not Improve.Findings.Safe_Relative_Path ("../outside"), "parent traversal was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("src//unit.adb"), "empty path component was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("/absolute/path"), "absolute path was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path ("C:\\outside"), "drive path was accepted");
            Assert (not Improve.Findings.Safe_Relative_Path (".."), "terminal parent traversal was accepted");
         when Projects_CLI =>
            declare
               Data   : constant Fixture := Build_Fixture ("projects_cli");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute (Args ("projects|--database|" & To_String (Data.Database) & "|--format|json"));
            begin
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       """command"":""projects""") > 0, "projects JSON inspection failed");
               Remove (Data);
            end;
         when Findings_CLI =>
            declare
               Data   : constant Fixture := Build_Fixture ("findings_cli");
               Result : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("findings|--database|" & To_String (Data.Database) & "|--project|" &
                          Id_Image (Data.Project) & "|--format|json"));
            begin
               Assert (Result.Exit_Code = 0 and then Ada.Strings.Fixed.Index (To_String (Result.Output),
                       "fixture-manifest") > 0, "findings JSON inspection failed: " & To_String (Result.Errors));
               Remove (Data);
            end;
         when Complete_Strategy_Registry =>
            for Indicator in Ada_Quality.Types.Indicator_Id loop
               declare Strategy : constant Improve.Rules.Remediation_Strategy :=
                 Improve.Rules.Strategy_For (Indicator);
               begin
                  Assert (Strategy.Indicator = Indicator, "strategy registry returned the wrong indicator");
                  Assert (Length (Strategy.Title) > 0 and then Length (Strategy.Acceptance) > 0 and then
                          Length (Strategy.Verification) > 0,
                          "strategy metadata is incomplete for " & Ada_Quality.Types.Image (Indicator));
               end;
            end loop;
            for Kind in Improve.Rules.Strategy_Kind loop
               Assert (Improve.Rules.Image (Kind) /= "", "strategy kind has no stable spelling");
            end loop;
            for Kind in Improve.Model.Candidate_Kind loop
               Assert (Improve.Model.Image (Kind) /= "", "candidate kind has no stable spelling");
            end loop;
            for Value in Improve.Model.Priority loop
               Assert (Improve.Model.Image (Value) /= "", "priority has no stable spelling");
            end loop;
            for Value in Improve.Model.Quality_Outcome loop
               Assert (Improve.Model.Image (Value) /= "", "quality outcome has no stable spelling");
            end loop;
         when Deterministic_Planner =>
            declare
               Data  : constant Fixture := Build_Fixture ("deterministic_plan");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project  : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  First    : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
                  Second   : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
               begin
                  Assert (First.Fingerprint = Second.Fingerprint, "equivalent planning was not deterministic");
                  Assert (First.Tasks.Length = 3, "fixture did not create three bounded tasks");
                  declare Coverage_Is_Investigation : Boolean := False; begin
                     for Spec of First.Tasks loop
                        if To_String (Spec.Title) = "Investigate missing coverage evidence" then
                           Coverage_Is_Investigation := Spec.Kind = Improve.Model.Investigation_Candidate;
                        end if;
                     end loop;
                     Assert (Coverage_Is_Investigation, "aggregate coverage invented an implementation scope");
                  end;
                  for Spec of First.Tasks loop
                     Assert (Length (Spec.Acceptance) > 0 and then Length (Spec.Scope) > 0,
                             "planner produced an underspecified task");
                  end loop;
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Planner_Grouping_And_Splitting =>
            declare
               Data  : constant Fixture := Build_Fixture ("planner_split");
               Store : Improve.Source.Repository;
            begin
               Improve.Source.Open (Store, To_String (Data.Database));
               declare
                  Project  : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Store, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
                  Original : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  Values   : Improve.Model.Finding_Vectors.Vector;
                  Duplicate : Improve.Model.Finding_Reference := Original.First_Element;
                  Grouped_Settings : constant Improve.Config.Settings := Improve.Config.Defaults;
                  Split_Settings   : Improve.Config.Settings := Improve.Config.Defaults;
               begin
                  Duplicate.Fingerprint := To_Unbounded_String ("second-manifest-finding");
                  Values.Append (Original.First_Element);
                  Values.Append (Duplicate);
                  Split_Settings.Maximum_Findings_Per_Task := 1;
                  declare
                     Grouped : constant Improve.Model.Plan_Revision :=
                       Improve.Planner.Generate (Selected, Values, Grouped_Settings);
                     Split : constant Improve.Model.Plan_Revision :=
                       Improve.Planner.Generate (Selected, Values, Split_Settings);
                  begin
                     Assert (Grouped.Tasks.Length = 1, "related findings were not consolidated");
                     Assert (Grouped.Tasks.First_Element.Finding_Keys.Length = 2,
                             "grouped task lost a finding relationship");
                     Assert (Split.Tasks.Length = 2, "oversized work was not split at the configured limit");
                  end;
               end;
               Improve.Source.Close (Store);
               Remove (Data);
            end;
         when Plan_Fingerprint_Severity_Sensitive =>
            declare
               Data    : constant Fixture := Build_Fixture
                 ("severity_fingerprint", Multiple_Structure => True,
                  Second_Structure_Severity => Ada_Quality.Types.Low);
               Quality : Improve.Source.Repository;
               Low_Settings  : Improve.Config.Settings := Improve.Config.Defaults;
               High_Settings : Improve.Config.Settings := Improve.Config.Defaults;
               Store   : Improve.Storage.Store;
               First   : Improve.Storage.Save_Result;
               Second  : Improve.Storage.Save_Result;
            begin
               Low_Settings.Minimum_Severity := Improve.Config.Low;
               High_Settings.Minimum_Severity := Improve.Config.High;
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Low_Findings : constant Improve.Model.Finding_Vectors.Vector :=
                    Improve.Findings.Normalize (Selected, Ada_Quality.Types.Low, True);
                  High_Findings : constant Improve.Model.Finding_Vectors.Vector :=
                    Improve.Findings.Normalize (Selected, Ada_Quality.Types.High, True);
                  Low_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Low_Findings, Low_Settings);
                  High_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, High_Findings, High_Settings);
               begin
                  Improve.Source.Close (Quality);
                  Assert
                    (Low_Findings.Length > High_Findings.Length and then
                     Low_Plan.Fingerprint /= High_Plan.Fingerprint,
                     "severity-dependent finding membership collided in the plan fingerprint");
                  Improve.Storage.Open
                    (Store, To_String (Data.Directory) & "/severity-improve.db", Writable => True);
                  First := Improve.Storage.Save (Store, Low_Plan);
                  Second := Improve.Storage.Save (Store, High_Plan);
                  Improve.Storage.Close (Store);
                  Assert
                    (not First.Existing and then not Second.Existing and then Second.Plan.Revision = 2 and then
                     Second.Plan.Findings.Length = High_Findings.Length,
                     "changed severity threshold silently returned an older plan revision");
               end;
               Remove (Data);
            end;
         when Plan_Fingerprint_Ignores_Unrelated_Snapshot =>
            declare
               Data       : constant Fixture := Build_Fixture ("unrelated_snapshot");
               Quality    : Improve.Source.Repository;
               State_Path : constant String := To_String (Data.Directory) & "/snapshot-improve.db";
               First_Plan : Improve.Model.Plan_Revision;
               First_Save : Improve.Storage.Save_Result;
               Second_Save : Improve.Storage.Save_Result;
               First_Snapshot : Unbounded_String;
            begin
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
               begin
                  First_Plan := Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
                  First_Snapshot := Selected.Baseline.Snapshot_Id;
               end;
               Improve.Source.Close (Quality);
               declare State : Improve.Storage.Store; begin
                  Improve.Storage.Open (State, State_Path, Writable => True);
                  First_Save := Improve.Storage.Save (State, First_Plan);
                  Improve.Storage.Close (State);
               end;
               declare Other : constant Fixture := Add_Fixture_Project (Data, "unrelated_project"); begin
                  Assert (Other.Project /= Data.Project, "unrelated project did not receive a separate identity");
               end;
               Improve.Source.Open (Quality, To_String (Data.Database));
               declare
                  Project : constant Improve.Model.Project_Reference :=
                    Improve.Source.Resolve_Project (Quality, Id_Image (Data.Project));
                  Selected : constant Improve.Source.Selection :=
                    Improve.Source.Select_Assessment (Quality, Project, Data.Run);
                  Findings : constant Improve.Model.Finding_Vectors.Vector := Improve.Findings.Normalize (Selected);
                  Second_Plan : constant Improve.Model.Plan_Revision :=
                    Improve.Planner.Generate (Selected, Findings, Improve.Config.Defaults);
               begin
                  Assert
                    (Selected.Baseline.Snapshot_Id /= First_Snapshot and then
                     Second_Plan.Fingerprint = First_Plan.Fingerprint,
                     "unrelated quality database state changed semantic plan identity");
                  Improve.Source.Close (Quality);
                  declare State : Improve.Storage.Store; begin
                     Improve.Storage.Open (State, State_Path, Writable => True);
                     Second_Save := Improve.Storage.Save (State, Second_Plan);
                     Improve.Storage.Close (State);
                  end;
               end;
               Assert
                 (not First_Save.Existing and then Second_Save.Existing and then Second_Save.Plan.Revision = 1,
                  "unrelated assessment created an unnecessary plan revision");
               Remove (Data);
            end;
         when Dependency_Cycle_Rejected =>
            declare
               procedure Expect_Rejection
                 (Values : Improve.Model.Task_Vectors.Vector;
                  Label  : String) is
                  Rejected : Boolean := False;
               begin
                  begin
                     Improve.Dependencies.Validate (Values);
                  exception
                     when Improve.Data_Error => Rejected := True;
                  end;
                  Assert (Rejected, Label & " was accepted");
               end Expect_Rejection;

               function Make_Task (Identity : String) return Improve.Model.Task_Specification is
                  Result : Improve.Model.Task_Specification;
               begin
                  Result.Id := To_Unbounded_String (Identity);
                  return Result;
               end Make_Task;

               Values : Improve.Model.Task_Vectors.Vector;
               First  : Improve.Model.Task_Specification;
               Second : Improve.Model.Task_Specification;
            begin
               Improve.Dependencies.Validate (Values);
               Values.Append (Make_Task ("IMP-VALID-A"));
               Second := Make_Task ("IMP-VALID-B");
               Second.Dependencies.Append (To_Unbounded_String ("IMP-VALID-A"));
               Values.Append (Second);
               Improve.Dependencies.Validate (Values);

               Values.Clear;
               Values.Append (Make_Task (""));
               Expect_Rejection (Values, "empty task identity");

               Values.Clear;
               Values.Append (Make_Task ("IMP-DUP"));
               Values.Append (Make_Task ("IMP-DUP"));
               Expect_Rejection (Values, "duplicate task identity");

               Values.Clear;
               First := Make_Task ("IMP-UNKNOWN");
               First.Dependencies.Append (To_Unbounded_String ("IMP-MISSING"));
               Values.Append (First);
               Expect_Rejection (Values, "unknown dependency");

               Values.Clear;
               First := Make_Task ("IMP-SELF");
               First.Dependencies.Append (First.Id);
               Values.Append (First);
               Expect_Rejection (Values, "self dependency");

               Values.Clear;
               First := Make_Task ("IMP-EDGE");
               First.Dependencies.Append (To_Unbounded_String ("IMP-TARGET"));
               First.Dependencies.Append (To_Unbounded_String ("IMP-TARGET"));
               Values.Append (First);
               Values.Append (Make_Task ("IMP-TARGET"));
               Expect_Rejection (Values, "duplicate dependency edge");

               Values.Clear;
               First := Make_Task ("IMP-A");
               First.Dependencies.Append (To_Unbounded_String ("IMP-B"));
               Second := Make_Task ("IMP-B");
               Second.Dependencies.Append (To_Unbounded_String ("IMP-A"));
               Values.Append (First);
               Values.Append (Second);
               Expect_Rejection (Values, "dependency cycle");
            end;
         when Dense_Contract_Fingerprints =>
            declare
               Plan : Improve.Model.Plan_Revision;
            begin
               for Index in 1 .. 32 loop
                  declare
                     Spec : Improve.Model.Task_Specification;
                  begin
                     Spec.Id := To_Unbounded_String ("IMP-DENSE-" & Id_Image (Index));
                     Spec.Title := Spec.Id;
                     Spec.Acceptance := To_Unbounded_String ("complete");
                     for Dependency in 1 .. Index - 1 loop
                        Spec.Dependencies.Append
                          (To_Unbounded_String ("IMP-DENSE-" & Id_Image (Dependency)));
                     end loop;
                     Plan.Tasks.Append (Spec);
                  end;
               end loop;
               declare
                  First : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
                    Improve.Model.Effective_Task_Contracts (Plan);
                  Second : constant Improve.Model.Task_Contract_Binding_Vectors.Vector :=
                    Improve.Model.Effective_Task_Contracts (Plan);
               begin
                  Assert
                    (First.Length = Plan.Tasks.Length and then
                     First.Last_Element.Fingerprint = Second.Last_Element.Fingerprint,
                     "dense dependency contracts were not calculated deterministically");
               end;
            end;
      when others =>
         raise Program_Error with "non-domain case routed to domain test subunit";
   end case;
end Run_Domain_Test;
