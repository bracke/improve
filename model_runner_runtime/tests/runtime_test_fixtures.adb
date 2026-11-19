with Ada.Directories;
with Ada.Strings.Unbounded;

with Ada_Quality.Checks;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Project_Tools.Files;

package body Runtime_Test_Fixtures is
   use Ada.Strings.Unbounded;

   procedure Build_Quality_Fixture
     (Database : String;
      Target   : String;
      Project  : out Positive) is
      use Ada_Quality.Types;
      Store : Ada_Quality.Storage.Store;
      Run   : Positive;
      Value : Assessment;
   begin
      Ada.Directories.Create_Directory (Target);
      Project_Tools.Files.Write_Text_File
        (Target & "/alire.toml",
         "name = ""runtime_fixture""" & ASCII.LF &
         "version = ""0.1.0-dev""" & ASCII.LF &
         "licenses = ""MIT""" & ASCII.LF);
      Ada_Quality.Storage.Open (Store, Database);
      Project := Ada_Quality.Storage.Add_Project (Store, Target);
      declare
         Source : constant String := Ada_Quality.Checks.Source_Fingerprint (Target);
      begin
         Run := Ada_Quality.Storage.Start_Assessment (Store, Project, Source, "runtime-policy");
         Value.Id := Run;
         Value.Project_Id := Project;
         Value.Project_Path := To_Unbounded_String (Target);
         Value.Source_Fingerprint := To_Unbounded_String (Source);
         Value.Policy_Fingerprint := To_Unbounded_String ("runtime-policy");
         Value.Toolchain_Fingerprint := To_Unbounded_String ("gnat-15.2.1");
         Value.Status := Assessment_Completed;
      end;
      for Indicator in Indicator_Id loop
         Value.Results.Append
           (Indicator_Result'
              (Indicator   => Indicator,
               Execution   => Succeeded,
               Compliance  => Pass,
               Applicable  => True,
               Summary     => To_Unbounded_String ("pass"),
               Evidence    => To_Unbounded_String ("runtime fixture"),
               Measurement => (Kind => Boolean_Value, Boolean_Data => True),
               Findings    => <>));
      end loop;
      declare
         Index  : constant Positive := Value.Results.First_Index + Indicator_Id'Pos (STR_01);
         Result : Indicator_Result := Value.Results (Index);
      begin
         Result.Compliance := Violation;
         Result.Summary := To_Unbounded_String ("runtime fixture violation");
         Result.Measurement := (Kind => Boolean_Value, Boolean_Data => False);
         Result.Findings.Append
           (Finding'
              (Indicator     => STR_01,
               Rule          => To_Unbounded_String ("runtime.fixture"),
               Level         => High,
               Message       => To_Unbounded_String ("exercise model-assisted remediation"),
               Relative_Path => To_Unbounded_String ("alire.toml"),
               Line          => 1,
               Fingerprint   => To_Unbounded_String
                 (Ada_Quality.Finding_Identity.Create
                    (STR_01, "runtime.fixture", "alire.toml", "exercise model-assisted remediation"))));
         Value.Results.Replace_Element (Index, Result);
      end;
      if Ada_Quality.Storage.Publish (Store, Value) /= Run then
         raise Program_Error with "runtime fixture assessment identity changed";
      end if;
      Ada_Quality.Storage.Close (Store);
   end Build_Quality_Fixture;
end Runtime_Test_Fixtures;
