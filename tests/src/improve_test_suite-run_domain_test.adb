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
            declare
               Previous : constant Terminal_Styles.Color_Policy :=
                 Terminal_Styles.Current_Color_Policy;
            begin
               declare
                  Style : Improve.Presentation.Styling_Scope :=
                    Improve.Presentation.Configure
                      (Improve.Config.Terminal_Format, Improve.Config.Color_Always);
                  pragma Unreferenced (Style);
               begin
                  Assert
                    (Improve.Presentation.Header ("Improve") /= "" and then
                     Terminal_Styles.Current_Color_Policy = Terminal_Styles.Color_Always,
                     "scoped terminal style was not applied");
                  declare
                     Nested : Improve.Presentation.Styling_Scope :=
                       Improve.Presentation.Configure
                         (Improve.Config.Terminal_Format, Improve.Config.Color_Never);
                     pragma Unreferenced (Nested);
                  begin
                     Assert
                       (Terminal_Styles.Current_Color_Policy = Terminal_Styles.Color_Never,
                        "nested terminal style was not applied");
                  end;
                  Assert
                    (Terminal_Styles.Current_Color_Policy = Terminal_Styles.Color_Always,
                     "nested terminal style did not restore its owner scope");
               end;
               Assert
                 (Terminal_Styles.Current_Color_Policy = Previous,
                  "terminal style leaked beyond its rendering scope");
            end;
         end;
      when Digest =>
         Assert
           (Improve.Stable_Digest ("") =
              "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" and then
            Improve.Stable_Digest ("improve") = Improve.Stable_Digest ("improve") and then
            Improve.Stable_Digest ("improve") /= Improve.Stable_Digest ("Improve"),
            "SHA-256 stable digest is incorrect or nondeterministic");
         declare
            Left  : constant Improve.Model.UString_Vectors.Vector :=
              [To_Unbounded_String ("a|b"), To_Unbounded_String ("c")];
            Right : constant Improve.Model.UString_Vectors.Vector :=
              [To_Unbounded_String ("a"), To_Unbounded_String ("b|c")];
         begin
            Assert
              (Improve.Model.Canonical_Key (Left) /= Improve.Model.Canonical_Key (Right),
               "canonical component encoding lost a field boundary");
         end;
         declare
            Seed   : constant String := [1 .. 64 => '0'];
            Digest : constant String := Improve.Stable_Digest ("canonical");
            Public_Key, Signature : Unbounded_String;
            Rejected : Boolean := False;
         begin
            Improve.Audit_Artifacts.Sign (Digest, Seed, Public_Key, Signature);
            declare
               Text : constant String :=
                 "{""data"":{""canonical_payload"":""canonical"",""bundle_digest"":""" & Digest &
                 """,""public_key"":""" & To_String (Public_Key) & """,""signature"":""" &
                 To_String (Signature) & """}}";
            begin
               Improve.Audit_Artifacts.Verify (Text);
               begin
                  Improve.Audit_Artifacts.Verify
                    (Text (Text'First .. Text'Last - 4) &
                     (if Text (Text'Last - 3) = '0' then "1" else "0") & Text (Text'Last - 2 .. Text'Last));
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "altered signed audit artifact was accepted");
            end;
         end;
      when Plan_Diff_Explanation =>
         declare
            Data    : constant Fixture := Build_Fixture ("plan_diff");
            Earlier : Improve.Model.Plan_Revision := Draft_For (Data);
            Later   : Improve.Model.Plan_Revision;
         begin
            Earlier.Plan_Id := To_Unbounded_String ("PLAN-000001");
            Earlier.Revision := 1;
            Later := Earlier;
            Later.Revision := 2;
            Later.Baseline.Run_Id := Earlier.Baseline.Run_Id + 1;
            Later.Tasks (Later.Tasks.First_Index).Title := To_Unbounded_String ("Changed contract");
            declare
               Compared : constant Improve.Results.Plan_Comparison :=
                 Improve.Plan_Diffs.Compare (Earlier, Later);
               Initial : constant Improve.Results.Plan_Comparison :=
                 Improve.Plan_Diffs.Explain (Earlier, Earlier);
            begin
               Assert
                 (Compared.Changed and then Compared.Reasons.Length >= 2 and then Initial.Changed and then
                  not Initial.Reasons.Is_Empty,
                  "plan revision differences were not explained");
               Assert
                 (Ada.Strings.Fixed.Index
                    (Improve.JSON.Plan_Comparison (Compared, False), "field changed: title") > 0
                  and then
                  Ada.Strings.Fixed.Index
                    (Improve.Presentation.Plan_Comparison (Compared, True), "Plan revision explanation") > 0,
                  "plan comparison adapters omitted deterministic reasons");
            end;
            Remove (Data);
         end;
      when Inspection_Filters =>
         declare
            Data  : constant Fixture := Build_Fixture ("inspection_filters");
            Draft : constant Improve.Model.Plan_Revision := Draft_For (Data);
            Input : Improve.Results.Finding_List :=
              (Project_Id    => Draft.Project.Id,
               Project       => Draft.Project.Name,
               Run_Id        => Draft.Baseline.Run_Id,
               Assessment_Id => Draft.Baseline.Evidence_Id,
               Snapshot_Id   => Draft.Baseline.Snapshot_Id,
               Values        => Draft.Findings);
         begin
            declare
               Finding : Improve.Model.Finding_Reference := Input.Values.First_Element;
            begin
               Finding.Indicator := Ada_Quality.Types.SEC_01;
               Finding.Level := Ada_Quality.Types.Critical;
               Finding.Relative_Path := To_Unbounded_String ("src/security.adb");
               Input.Values.Append (Finding);
            end;
            declare
               Filtered : constant Improve.Results.Finding_List :=
                 Improve.Inspection_Filters.Findings
                   (Input, Indicator => "SEC-01", Severity => "critical", Path => "security");
            begin
               Assert
                 (Filtered.Values.Length = 1 and then
                  Filtered.Values.First_Element.Indicator = Ada_Quality.Types.SEC_01,
                  "inspection-only finding filters changed or retained the wrong evidence");
            end;
            Remove (Data);
         end;
      when Doctor_Read_Only =>
         declare
            Data    : constant Fixture := Build_Fixture ("doctor");
            Missing : constant String := To_String (Data.Directory) & "/missing-improve.db";
            Report  : constant Improve.Results.Diagnostic_Report :=
              Improve.Operations.Diagnostics.Run
                (To_String (Data.Database), Missing, Id_Image (Data.Project), Improve.Config.Defaults);
            Release_Report : constant Improve.Results.Diagnostic_Report :=
              Improve.Operations.Diagnostics.Run
                (To_String (Data.Database), Missing, Id_Image (Data.Project), Improve.Config.Defaults,
                 Resolve_Release => True);
         begin
            Assert
              (Report.Healthy and then not Report.Checks.Is_Empty and then
               not Ada.Directories.Exists (Missing),
               "doctor failed healthy read-only diagnostics or created state");
            Assert (not Release_Report.Checks.Is_Empty, "release diagnostics returned no checks");
            Assert
              (Ada.Strings.Fixed.Index (Improve.JSON.Diagnostics (Report), """healthy"":true") > 0 and then
               Ada.Strings.Fixed.Index (Improve.Presentation.Diagnostics (Report), "PASS") > 0,
               "diagnostic adapters omitted health state");
            Remove (Data);
         end;
      when Property_And_Scale =>
         declare
            Earlier : Improve.Model.Plan_Revision;
            Later   : Improve.Model.Plan_Revision;
         begin
            Earlier.Plan_Id := To_Unbounded_String ("PLAN-SCALE");
            Earlier.Project := (Id => 1, Name | Path | Database_Id => Null_Unbounded_String);
            Earlier.Baseline :=
              (Project_Id | Run_Id => 1,
               Source_Id | Policy_Id | Toolchain_Id | Evidence_Id | Snapshot_Id => Null_Unbounded_String);
            for Index in 1 .. 500 loop
               Earlier.Tasks.Append
                 (Improve.Model.Task_Specification'
                    (Id => To_Unbounded_String ("TASK-" & Id_Image (Index)),
                     Title => To_Unbounded_String ("task " & Id_Image (Index)), others => <>));
            end loop;
            Later := Earlier;
            Later.Revision := 2;
            Later.Tasks (Later.Tasks.Last_Index).Title := To_Unbounded_String ("changed at scale");
            declare
               Same    : constant Improve.Results.Plan_Comparison := Improve.Plan_Diffs.Compare (Earlier, Earlier);
               Changed : constant Improve.Results.Plan_Comparison := Improve.Plan_Diffs.Compare (Earlier, Later);
            begin
               Assert
                 (not Same.Changed and then Same.Reasons.Is_Empty and then Changed.Changed and then
                  Changed.Reasons.Length = 1 and then
                  Ada.Strings.Fixed.Index (To_String (Changed.Reasons.First_Element), "field changed: title") > 0,
                  "plan diff identity or 500-task scale property failed");
            end;
            Improve_JSON_Output_Testing.Check_All (Earlier);
         end;
         declare
            Data  : constant Fixture := Build_Fixture ("audit_bundle");
            Draft : Improve.Model.Plan_Revision := Draft_For (Data);
            Store : Improve.Storage.Store;
            State_Path : constant String := To_String (Data.Directory) & "/improve.db";
         begin
            Improve.Storage.Open (Store, State_Path, Writable => True);
            declare Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Draft); begin
               Draft := Saved.Plan;
            end;
            Improve.Storage.Approve (Store, To_String (Draft.Plan_Id), Draft.Revision);
            Improve.Storage.Close (Store);
            declare Bundle : constant Improve.Results.Audit_Bundle :=
              Improve.Operations.Audit.Run (State_Path, To_String (Draft.Plan_Id));
            begin
               Assert
                 (Bundle.Approved and then Bundle.Plan.Fingerprint = Draft.Fingerprint and then
                  Ada.Strings.Fixed.Index (Improve.JSON.Audit (Bundle), """command"":""audit""") > 0,
                  "read-only audit bundle omitted exact plan approval or provenance");
            end;
            declare
               Common : constant String := "|--state|" & State_Path & "|--format|json";
               Graph  : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("plan|graph|" & To_String (Draft.Plan_Id) & "|--state|" & State_Path & "|--format|dot"));
               Plans  : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("plan|list|--database|" & To_String (Data.Database) & "|--project|" &
                          Id_Image (Data.Project) & Common & "|--limit|1|--cursor|0"));
               Tasks  : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("tasks|--database|" & To_String (Data.Database) & "|--project|" &
                          Id_Image (Data.Project) & Common & "|--limit|1|--cursor|0"));
               Audit  : constant Improve.CLI.Outcome :=
                 Improve.CLI.Execute
                   (Args ("audit|" & To_String (Draft.Plan_Id) & Common & "|--limit|1|--cursor|0"));
            begin
               Assert
                 (Graph.Exit_Code = 0 and then Plans.Exit_Code = 0 and then Tasks.Exit_Code = 0 and then
                  Audit.Exit_Code = 0,
                  "graph or paged state inspection command failed");
            end;
            Remove (Data);
         end;
         declare
            Builder  : Improve.Canonical_Digests.Builder;
            Expected : constant String :=
              Improve.Stable_Digest (Natural'Image (1) & ":x" & Natural'Image (1) & ":y");
            Rejected : Boolean := False;
         begin
            Improve.Canonical_Digests.Initialize (Builder);
            Improve.Canonical_Digests.Add (Builder, "x", "y");
            Assert
              (Improve.Canonical_Digests.Finish (Builder) = Expected,
               "streaming canonical digest changed the established encoding");
            Improve.Canonical_Digests.Initialize (Builder, Maximum_Value_Bytes => 1);
            begin
               Improve.Canonical_Digests.Add (Builder, "x", "too large");
            exception
               when Improve.Data_Error => Rejected := True;
            end;
            Assert (Rejected, "canonical digest ignored its value-byte limit");
         end;
         declare
            Earlier : Improve.Model.Plan_Revision;
            Later   : Improve.Model.Plan_Revision;
         begin
            Earlier.Project :=
              (Id => 1, Name | Path | Database_Id => Null_Unbounded_String);
            Earlier.Baseline :=
              (Project_Id | Run_Id => 1,
               Source_Id | Policy_Id | Toolchain_Id | Evidence_Id | Snapshot_Id => Null_Unbounded_String);
            Earlier.Created_At := Ada.Calendar.Time_Of (2026, 1, 1);
            Later := Earlier;
            Later.Created_At := Ada.Calendar.Time_Of (2026, 1, 2);
            Assert
              (Improve.Model.Plan_Content_Fingerprint (Earlier) /=
                 Improve.Model.Plan_Content_Fingerprint (Later),
               "persisted-content fingerprint ignored creation chronology");
         end;
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
                  Value : constant Improve.Model.Project_Reference := Improve.Source.Resolve_Project (Store, "");
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
                     Value : constant Improve.Source.Selection := Improve.Source.Select_Assessment (Store, Project);
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
                  begin
                     null;
                  end;
               exception
                  when Improve.Dependency_Error => Rejected := True;
               end;
            end;
            Assert (Rejected, "explicit interrupted assessment was accepted");
            Improve.Source.Close (Store);
            Remove (Data);
         end;
      when Assessment_Evidence_Bounded =>
         declare
            Data     : constant Fixture := Build_Fixture ("bounded-assessment");
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
                       Improve.Source.Select_Assessment (Store, Project, Maximum_Bytes => 1);
                     pragma Unreferenced (Chosen);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
            end;
            Assert (Rejected, "assessment fingerprinting ignored its evidence byte limit");
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
               Assert (Values.Length = 3, "findings were not classified into three candidates");
               Assert
                 (To_String (Values.First_Element.Fingerprint) =
                    Finding_Fingerprint
                      (Ada_Quality.Types.STR_01, "manifest.invalid", "alire.toml", "manifest is invalid"),
                  "Ada Quality finding fingerprint was not preserved");
               declare
                  Finding_Limit_Rejected : Boolean := False;
                  Byte_Limit_Rejected    : Boolean := False;
               begin
                  begin
                     declare
                        Ignored : constant Improve.Model.Finding_Vectors.Vector :=
                          Improve.Findings.Normalize (Chosen, Maximum_Findings => 2);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Data_Error => Finding_Limit_Rejected := True;
                  end;
                  begin
                     declare
                        Ignored : constant Improve.Model.Finding_Vectors.Vector :=
                          Improve.Findings.Normalize (Chosen, Maximum_Bytes => 8);
                        pragma Unreferenced (Ignored);
                     begin
                        null;
                     end;
                  exception
                     when Improve.Data_Error => Byte_Limit_Rejected := True;
                  end;
                  Assert
                    (Finding_Limit_Rejected and then Byte_Limit_Rejected,
                     "assessment normalization limits were not enforced during ingestion");
               end;
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
         Assert (not Improve.Findings.Safe_Relative_Path ("C:\outside"), "drive path was accepted");
         Assert (not Improve.Findings.Safe_Relative_Path (".."), "terminal parent traversal was accepted");
         Assert (not Improve.Findings.Safe_Relative_Path ("."), "terminal current-directory alias was accepted");
         Assert
           (not Improve.Findings.Safe_Relative_Path ("src/./unit.adb"),
            "current-directory path alias was accepted");
         Assert
           (not Improve.Findings.Safe_Relative_Path ("src/unsafe" & Character'Val (10) & "instruction.adb"),
            "control character in path was accepted");
         Assert
           (not Improve.Findings.Safe_Relative_Path
              ("src/" & Character'Val (16#E2#) & Character'Val (16#80#) &
               Character'Val (16#AE#) & "unit.adb"),
            "bidirectional override in path was accepted");
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
            Paged : constant Improve.CLI.Outcome :=
              Improve.CLI.Execute
                (Args ("findings|--database|" & To_String (Data.Database) & "|--project|" &
                       Id_Image (Data.Project) & "|--format|json|--limit|1|--cursor|1"));
         begin
            Assert
              (Result.Exit_Code = 0 and then
               Ada.Strings.Fixed.Index
                 (To_String (Result.Output),
                  Finding_Fingerprint
                    (Ada_Quality.Types.STR_01, "manifest.invalid", "alire.toml", "manifest is invalid")) > 0,
               "findings JSON inspection failed: " & To_String (Result.Errors));
            Assert
              (Paged.Exit_Code = 0 and then
               Ada.Strings.Fixed.Index (To_String (Paged.Output), """command"":""findings""") > 0,
               "findings cursor page was not applied");
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
      when others =>
         raise Program_Error with "non-domain case routed to domain test subunit";
   end case;
end Run_Domain_Test;
