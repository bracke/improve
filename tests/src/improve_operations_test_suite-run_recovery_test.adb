separate (Improve_Operations_Test_Suite)
procedure Run_Recovery_Test (Item : in out Case_Test) is
begin
   case Item.Id is
         when Interrupted_Publication_Recovery =>
            declare
               Data      : constant Fixture := Build_Fixture ("recover");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               pragma Unreferenced (Operation);
               First     : Improve.CLI.Outcome;
               Second    : Improve.CLI.Outcome;
            begin
               Assert (Planned.Exit_Code = 0, "recovery fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               declare Published : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish
                   (To_String (Plan.Project.Path), Improve.Operations.Publication_Namespace (State),
                    Plan, "auto");
               begin
                  Assert (Published.Tasks.Length = 3,
                          "interrupted recovery fixture did not commit harness tasks");
               end;
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/after_harness_commit.adb",
                  "procedure After_Harness_Commit is begin null; end After_Harness_Commit;" & ASCII.LF);
               First := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Second := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Assert (First.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (First.Output), """operations_recovered"":1") > 0 and then
                         Ada.Strings.Fixed.Index (To_String (First.Output), """tasks_recovered"":3") > 0,
                       "interrupted publication was not recovered");
               Assert (Second.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                         (To_String (Second.Output), """operations_recovered"":0") > 0,
                       "repeated recovery was not idempotent");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert (Improve.Storage.Pending_Publications (Improve_State).Is_Empty and then
                            Improve.Storage.Publications (Improve_State, "PLAN-000001").Length = 3,
                          "recovery did not durably complete mappings and journal state");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Recovery_Rejects_Stale_Uncommitted =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("recover_stale");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               Result    : Improve.CLI.Outcome;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               pragma Unreferenced (Operation);
            begin
               Assert (Planned.Exit_Code = 0, "stale recovery fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  Improve.Storage.Approve (Improve_State, "PLAN-000001", Plan.Revision);
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               Project_Tools.Files.Write_Text_File
                 (To_String (Data.Target) & "/stale_before_commit.adb",
                  "procedure Stale_Before_Commit is begin null; end Stale_Before_Commit;" & ASCII.LF);
               Result := Improve.CLI.Execute (Args ("recover|--state|" & State & "|--format|json"));
               Assert
                 (Result.Exit_Code = Improve.CLI.Failure_Exit and then Ada.Strings.Fixed.Index
                    (To_String (Result.Errors), "operation retained") > 0,
                  "recovery replayed stale uncommitted publication work");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "stale recovery created native tasks");
               Stores.Close (Harness);
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert
                    (Improve.Storage.Pending_Publications (Improve_State).Length = 1,
                     "stale recovery did not retain its pending operation");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Recovery_Rejects_Policy_Change =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("recover_policy");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               Rejected  : Boolean := False;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               pragma Unreferenced (Operation);
            begin
               Assert (Planned.Exit_Code = 0, "policy recovery fixture plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  Improve.Storage.Approve (Improve_State, "PLAN-000001", Plan.Revision);
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               declare
                  Ignored : constant Positive := Publish_Followup
                    (Data,
                     Source => Ada_Quality.Checks.Source_Fingerprint (To_String (Data.Target)),
                     Policy => "policy-b");
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
               begin
                  declare Report : constant Improve.Recovery.Recovery_Report :=
                    Improve.Recovery.Recover
                      (State, To_String (Data.Database), "auto", Maximum => 10);
                     pragma Unreferenced (Report);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Rejected and then Errors.Is_Ok (Status) and then Tasks.List (Harness).Is_Empty,
                  "recovery created native work after the quality policy changed");
               Stores.Close (Harness);
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  Assert
                    (Improve.Storage.Pending_Publications (Improve_State).Length = 1,
                     "policy-stale recovery did not retain its pending operation");
                  Improve.Storage.Close (Improve_State);
               end;
               Remove (Data);
            end;
         when Published_Task_Reused_Across_Revisions =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data       : constant Fixture := Build_Fixture ("revision_reuse");
               State      : constant String := To_String (Data.Directory) & "/improve.db";
               First_Plan : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Applied    : Improve.CLI.Outcome;
               Replanned  : Improve.CLI.Outcome;
               Run        : Positive;
               Old_Map    : Improve.State.Publication_Record;
               New_Map    : Improve.State.Publication_Record;
               Harness    : Stores.Store;
               Status     : Errors.Error_Info;
            begin
               Assert (First_Plan.Exit_Code = 0, "initial cross-revision plan failed");
               Initialize_Harness (To_String (Data.Target));
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert (Applied.Exit_Code = 0, "initial cross-revision publication failed");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Mapping of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if To_String (Mapping.Improve_Task_Id) = "IMP-000001" then Old_Map := Mapping; exit; end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Run := Publish_Followup
                 (Data, Structure_State => Structure_Failing,
                  Source => Ada_Quality.Checks.Source_Fingerprint (To_String (Data.Target)));
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "cross-revision replanning failed");
               Approve_Latest (State);
               Applied := Improve.CLI.Execute
                 (Args ("apply|PLAN-000001|--database|" & To_String (Data.Database) & "|--state|" & State &
                        "|--format|json"));
               Assert
                 (Applied.Exit_Code = 0 and then Ada.Strings.Fixed.Index
                    (To_String (Applied.Output), """recovered"":true") > 0,
                  "unchanged cross-revision task was not recovered");
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => False);
                  for Mapping of Improve.Storage.Publications (Improve_State, "PLAN-000001") loop
                     if Mapping.Improve_Task_Id = Old_Map.Improve_Task_Id then New_Map := Mapping; exit; end if;
                  end loop;
                  Improve.Storage.Close (Improve_State);
               end;
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3 and then
                  New_Map.Harness_Task_Id = Old_Map.Harness_Task_Id and then New_Map.Origin = Old_Map.Origin,
                  "unchanged task was duplicated or remapped across revisions");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Recovery_Uses_Exact_Revision =>
            declare
               package Errors renames Model_Runner.Errors;
               package Stores renames Model_Runner.Framework.Stores;
               package Tasks renames Model_Runner.Framework.Tasks;
               Data      : constant Fixture := Build_Fixture ("recovery_revision");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               Task_Ids  : Improve.Model.UString_Vectors.Vector;
               Operation : Positive;
               Run       : Positive;
               Replanned : Improve.CLI.Outcome;
               Recovered : Improve.Recovery.Recovery_Report;
               Harness   : Stores.Store;
               Status    : Errors.Error_Info;
               pragma Unreferenced (Operation);
            begin
               Assert (Planned.Exit_Code = 0, "exact-revision recovery plan failed");
               Initialize_Harness (To_String (Data.Target));
               declare Improve_State : Improve.Storage.Store; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop Task_Ids.Append (Spec.Id); end loop;
                  Operation := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", Task_Ids);
                  Improve.Storage.Close (Improve_State);
               end;
               declare Published : constant Improve.Workflow.Publication_Result :=
                 Improve.Workflow.Publish
                   (To_String (Data.Target), Improve.Operations.Publication_Namespace (State),
                    Plan, "auto");
               begin
                  Assert (Published.Tasks.Length = 3, "interrupted exact-revision publication failed");
               end;
               Run := Publish_Followup (Data);
               Replanned := Improve.CLI.Execute
                 (Args ("plan|--project|" & Id_Image (Data.Project) & "|--run|" & Id_Image (Run) &
                        "|--database|" & To_String (Data.Database) & "|--state|" & State & "|--format|json"));
               Assert (Replanned.Exit_Code = 0, "newer recovery fixture plan failed");
               Recovered := Improve.Recovery.Recover
                 (State, To_String (Data.Database), "not-a-current-kind", Maximum => 10);
               Assert
                 (Recovered.Operations_Recovered = 1 and then Recovered.Tasks_Recovered = 3,
                  "recovery substituted a newer plan revision");
               Stores.Open_To_Read (Harness, To_String (Data.Target), Status);
               Assert
                 (Errors.Is_Ok (Status) and then Tasks.List (Harness).Length = 3,
                  "exact-revision recovery duplicated or lost native tasks");
               Stores.Close (Harness);
               Remove (Data);
            end;
         when Recovery_Limit_Enforced =>
            declare
               Data      : constant Fixture := Build_Fixture ("recover_limit");
               State     : constant String := To_String (Data.Directory) & "/improve.db";
               Planned   : constant Improve.CLI.Outcome := Prepare_Verification_Plan (Data, State);
               Plan      : Improve.Model.Plan_Revision;
               All_Tasks : Improve.Model.UString_Vectors.Vector;
               One_Task  : Improve.Model.UString_Vectors.Vector;
               Rejected  : Boolean := False;
            begin
               Assert (Planned.Exit_Code = 0, "recovery limit fixture plan failed");
               declare Improve_State : Improve.Storage.Store; First, Second : Positive; begin
                  Improve.Storage.Open (Improve_State, State, Writable => True);
                  Plan := Improve.Storage.Load (Improve_State, "PLAN-000001");
                  for Spec of Plan.Tasks loop All_Tasks.Append (Spec.Id); end loop;
                  One_Task.Append (Plan.Tasks.First_Element.Id);
                  First := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", All_Tasks);
                  Second := Improve.Storage.Begin_Publication
                    (Improve_State, Plan, "remediation", One_Task);
                  Assert (First /= Second, "distinct recovery operations reused an identity");
                  Improve.Storage.Close (Improve_State);
               end;
               begin
                  declare
                     Report : constant Improve.Recovery.Recovery_Report :=
                       Improve.Recovery.Recover
                         (State, To_String (Data.Database), "auto", Maximum => 1);
                     pragma Unreferenced (Report);
                  begin
                     null;
                  end;
               exception
                  when Improve.Data_Error => Rejected := True;
               end;
               Assert (Rejected, "recovery operation limit was not enforced");
               Remove (Data);
            end;
         when Recover_Missing_State =>
            declare
               Root   : constant String := Hostkit.Fs.Create_Temporary_Directory ("improve-missing-state");
               Path   : constant String := Root & "/missing.db";
               Result : Improve.CLI.Outcome;
            begin
               Project_Tools.Files.Delete_File_If_Present (Path);
               Result := Improve.CLI.Execute (Args ("recover|--state|" & Path & "|--format|json"));
               Assert (Result.Exit_Code = Improve.CLI.Unavailable_Exit and then Length (Result.Output) = 0 and then
                         not Project_Tools.Files.File_Exists (Path),
                       "recover initialized missing state or returned the wrong exit code");
               Project_Tools.Files.Delete_Tree (Root);
            end;
      when others =>
         raise Program_Error with "case routed to the wrong operations test group";
   end case;
end Run_Recovery_Test;
