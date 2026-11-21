with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve.CLI;
with Improve.Model;
with Improve.Storage;
with Improve_Test_Support;
with Project_Tools.Files;

package body Improve_CLI_Output_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Improve_Test_Support;

   type Output_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Case_Access is access all Output_Case;

   overriding function Name (Item : Output_Case) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Output_Case);

   overriding function Name (Item : Output_Case) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("IMP_CLI_INSPECTION_OUTPUTS");
   end Name;

   overriding procedure Run_Test (Item : in out Output_Case) is
      pragma Unreferenced (Item);
      Data       : constant Fixture := Build_Fixture ("cli_outputs");
      Draft      : Improve.Model.Plan_Revision := Draft_For (Data);
      Store      : Improve.Storage.Store;
      State_Path : constant String := To_String (Data.Directory) & "/improve.db";
      Config_Path : constant String := To_String (Data.Directory) & "/improve.toml";
   begin
      declare
         Second : Improve.Model.Task_Specification := Draft.Tasks.First_Element;
      begin
         Second.Id := To_Unbounded_String ("IMP-PAGE-0002");
         Second.Title := To_Unbounded_String ("Second pagination task");
         Draft.Tasks.Append (Second);
         Draft.Fingerprint := To_Unbounded_String
           (Improve.Stable_Digest (To_String (Draft.Fingerprint) & ":pagination"));
      end;
      Project_Tools.Files.Write_Text_File
        (Config_Path,
         "schema_version = 2" & ASCII.LF & ASCII.LF &
         "[output]" & ASCII.LF & "maximum_output_items = 1" & ASCII.LF);
      Improve.Storage.Open (Store, State_Path, Writable => True);
      declare
         Saved : constant Improve.Storage.Save_Result := Improve.Storage.Save (Store, Draft);
      begin
         Draft := Saved.Plan;
      end;
      Improve.Storage.Close (Store);
      declare
         Common : constant String :=
           "|--state|" & State_Path & "|--config|" & Config_Path & "|--format|json";
         Second_Task_Id : constant String :=
           To_String (Draft.Tasks (Draft.Tasks.First_Index + 1).Id);
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
         Tasks_2 : constant Improve.CLI.Outcome :=
           Improve.CLI.Execute
             (Args ("tasks|--database|" & To_String (Data.Database) & "|--project|" &
                Id_Image (Data.Project) & Common & "|--limit|1|--cursor|1"));
         Too_Large : constant Improve.CLI.Outcome :=
           Improve.CLI.Execute
             (Args ("tasks|--database|" & To_String (Data.Database) & "|--project|" &
                Id_Image (Data.Project) & Common & "|--limit|2"));
      begin
         Assert
           (Graph.Exit_Code = 0 and then Plans.Exit_Code = 0 and then Tasks.Exit_Code = 0 and then
            Tasks_2.Exit_Code = 0 and then Too_Large.Exit_Code = Improve.CLI.Argument_Exit,
            "graph, plan-list, or task-list output routing failed:" &
            Natural'Image (Graph.Exit_Code) & Natural'Image (Plans.Exit_Code) &
            Natural'Image (Tasks.Exit_Code) & Natural'Image (Tasks_2.Exit_Code) &
            Natural'Image (Too_Large.Exit_Code) & " " & To_String (Tasks.Errors) &
            To_String (Tasks_2.Errors) & To_String (Too_Large.Errors));
         Assert
           (Ada.Strings.Fixed.Index (To_String (Tasks.Output), """next_cursor"":""1""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (Tasks.Output), Second_Task_Id) = 0 and then
            Ada.Strings.Fixed.Index (To_String (Tasks_2.Output), Second_Task_Id) > 0,
            "task pagination was applied after the output materialization cap: " &
            To_String (Tasks.Output) & " / " & To_String (Tasks_2.Output));
      end;
      Remove (Data);
   exception
      when others =>
         Improve.Storage.Close (Store);
         Remove (Data);
         raise;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Case_Access'(new Output_Case));
      return Result;
   end Suite;
end Improve_CLI_Output_Test_Suite;
