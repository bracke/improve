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
      when others =>
         raise Program_Error with "non-domain case routed to domain test subunit";
   end case;
end Run_Domain_Test;
