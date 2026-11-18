with Ada.Strings.Unbounded;
with Ada_Quality.Types;

--  Improve-owned configuration schema and validation.
package Improve.Config is
   --  Typed configuration schema, defaults, parsing, and deterministic rendering.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized configuration text.

   Default_Maximum_Quality_Database_Bytes : constant Positive := 1_073_741_824;
   --  Default maximum size of the Ada Quality database file.
   Default_Maximum_Assessment_Bytes       : constant Positive := 16_777_216;
   --  Default maximum complete typed assessment evidence size.
   Default_Maximum_Normalized_Finding_Bytes : constant Positive := 16_777_216;
   --  Default maximum normalized remediation finding size.
   Default_Maximum_Source_File_Bytes      : constant Positive := 16_777_216;
   --  Default maximum source bytes read from one file.
   Default_Maximum_Source_Total_Bytes     : constant Positive := 268_435_456;
   --  Default maximum source bytes read from one project.

   type Evidence_Limits is record
      Database_Bytes           : Positive := Default_Maximum_Quality_Database_Bytes;
      Assessment_Bytes         : Positive := Default_Maximum_Assessment_Bytes;
      Normalized_Finding_Bytes : Positive := Default_Maximum_Normalized_Finding_Bytes;
      Source_File_Bytes        : Positive := Default_Maximum_Source_File_Bytes;
      Source_Total_Bytes       : Positive := Default_Maximum_Source_Total_Bytes;
   end record;
   --  Shared limits for quality evidence and source identity construction.
   --  @field Database_Bytes Maximum Ada Quality database file bytes.
   --  @field Assessment_Bytes Maximum complete typed assessment evidence bytes.
   --  @field Normalized_Finding_Bytes Maximum normalized remediation finding bytes.
   --  @field Source_File_Bytes Maximum source bytes read from one file.
   --  @field Source_Total_Bytes Maximum source bytes read from one project.

   Default_Evidence_Limits : constant Evidence_Limits := (others => <>);
   --  Shared default evidence limits.

   type Output_Format is (Terminal_Format, JSON_Format, Markdown_Format, DOT_Format);
   --  User-visible output encoding.
   --  @enum Terminal_Format Human-readable terminal output.
   --  @enum JSON_Format Versioned JSON document.
   --  @enum Markdown_Format Human-readable Markdown report.
   --  @enum DOT_Format Graphviz dependency graph.
   type Color_Mode is (Color_Auto, Color_Always, Color_Never);
   --  Terminal color policy.
   --  @enum Color_Auto Enable color only for a suitable terminal.
   --  @enum Color_Always Force terminal color.
   --  @enum Color_Never Disable terminal color.
   type Severity_Level is (Info, Low, Medium, High, Critical);
   --  Minimum finding severity accepted by planning.
   --  @enum Info Informational findings.
   --  @enum Low Low-severity findings.
   --  @enum Medium Medium-severity findings.
   --  @enum High High-severity findings.
   --  @enum Critical Critical findings.
   type Selection_Mode is (Latest_Completed);
   --  Default assessment selection policy.
   --  @enum Latest_Completed Greatest successfully completed run identity.
   type Publication_Mode is (Candidate_Publication);
   --  Harness publication authorization policy.
   --  @enum Candidate_Publication Publish candidate tasks without accepting them.

   type Settings is record
      Quality_Database          : UString;
      Selection                 : Selection_Mode := Latest_Completed;
      Maximum_Quality_Projects  : Positive := 10_000;
      Maximum_Quality_Runs      : Positive := 1_000_000;
      Maximum_Quality_Findings  : Positive := 2_000_000;
      Maximum_Quality_Database_Bytes : Positive := Default_Maximum_Quality_Database_Bytes;
      Maximum_Assessment_Findings : Positive := 10_000;
      Maximum_Assessment_Bytes  : Positive := Default_Maximum_Assessment_Bytes;
      Maximum_Normalized_Finding_Bytes : Positive := Default_Maximum_Normalized_Finding_Bytes;
      Maximum_Source_File_Bytes : Positive := Default_Maximum_Source_File_Bytes;
      Maximum_Source_Total_Bytes : Positive := Default_Maximum_Source_Total_Bytes;
      Minimum_Severity          : Severity_Level := Low;
      Maximum_Tasks_Per_Plan    : Positive := 100;
      Maximum_Findings_Per_Task : Positive := 50;
      Allow_Investigation_Tasks : Boolean := True;
      Require_Review            : Boolean := True;
      Agent_Max_Context_Bytes   : Positive := 131_072;
      Agent_Max_File_Bytes      : Positive := 32_768;
      Agent_Max_Response_Bytes  : Positive := 131_072;
      Agent_Timeout_Seconds     : Positive := 60;
      Maximum_Output_Items      : Positive := 10_000;
      Maximum_History_Items     : Positive := 100_000;
      Maximum_Migration_Rows    : Positive := 1_000_000;
      Maximum_Persisted_Text_Bytes : Positive := 1_048_576;
      Maximum_Persisted_Total_Bytes : Positive := 67_108_864;
      Maximum_Recovery_Operations : Positive := 100;
      Task_Kind                 : UString;
      Publication               : Publication_Mode := Candidate_Publication;
      Require_Initialized       : Boolean := True;
      Require_Fresh_Measurement : Boolean := True;
      Require_Same_Policy       : Boolean := True;
      Require_Same_Toolchain    : Boolean := False;
      Require_No_New_Critical   : Boolean := True;
      Format                    : Output_Format := Terminal_Format;
      Color                     : Color_Mode := Color_Auto;
   end record;
   --  Validated configuration values.
   --  @field Quality_Database Default Ada Quality database path.
   --  @field Selection Assessment selection policy.
   --  @field Maximum_Quality_Projects Maximum project rows loaded from the quality database.
   --  @field Maximum_Quality_Runs Maximum run rows loaded from the quality database.
   --  @field Maximum_Quality_Findings Maximum finding rows loaded from the quality database.
   --  @field Maximum_Quality_Database_Bytes Maximum Ada Quality database file bytes accepted before loading.
   --  @field Maximum_Assessment_Findings Maximum findings normalized from one assessment.
   --  @field Maximum_Assessment_Bytes Maximum complete typed assessment evidence bytes.
   --  @field Maximum_Normalized_Finding_Bytes Maximum normalized remediation finding bytes.
   --  @field Maximum_Source_File_Bytes Maximum bytes read from one source file for identity construction.
   --  @field Maximum_Source_Total_Bytes Maximum source bytes read for one working-tree identity.
   --  @field Minimum_Severity Minimum planned severity.
   --  @field Maximum_Tasks_Per_Plan Maximum generated tasks.
   --  @field Maximum_Findings_Per_Task Maximum findings grouped into one task.
   --  @field Allow_Investigation_Tasks Whether incomplete evidence may create investigation work.
   --  @field Require_Review Whether generated work requires review.
   --  @field Agent_Max_Context_Bytes Maximum refinement context size.
   --  @field Agent_Max_File_Bytes Maximum source excerpt size.
   --  @field Agent_Max_Response_Bytes Maximum refinement response size.
   --  @field Agent_Timeout_Seconds Refinement request deadline.
   --  @field Maximum_Output_Items Maximum result items emitted by inspection.
   --  @field Maximum_History_Items Maximum persisted history records examined or appended by one operation.
   --  @field Maximum_Migration_Rows Maximum rows scanned while upgrading one Improve state database.
   --  @field Maximum_Persisted_Text_Bytes Maximum encoded bytes accepted from one persisted text field.
   --  @field Maximum_Persisted_Total_Bytes Maximum aggregate encoded row bytes read or written for one plan.
   --  @field Maximum_Recovery_Operations Maximum operations recovered in one invocation.
   --  @field Task_Kind Configured harness task kind or auto.
   --  @field Publication Harness publication policy.
   --  @field Require_Initialized Whether publication requires initialized harness state.
   --  @field Require_Fresh_Measurement Whether verification requires a newer run.
   --  @field Require_Same_Policy Whether verification requires policy identity.
   --  @field Require_Same_Toolchain Whether verification requires toolchain identity.
   --  @field Require_No_New_Critical Whether new critical findings cause regression.
   --  @field Format Default output format.
   --  @field Color Default color policy.

   function Defaults return Settings;
   --  Return documented schema-version-2 defaults.
   --  @return Complete default settings.

   function Evidence_Limits_Of (Item : Settings) return Evidence_Limits;
   --  Return the shared evidence limits from validated settings.
   --  @param Item Validated Improve settings.
   --  @return Evidence limits used by planning, inspection, publication, and recovery.

   function Quality_Severity (Value : Severity_Level) return Ada_Quality.Types.Severity;
   --  Convert planning severity configuration to the Ada Quality domain type.
   --  @param Value Configured severity level.
   --  @return Equivalent Ada Quality severity.

   function Load (Path : String) return Settings;
   --  Load and validate a configuration file; an empty path returns defaults.
   --  @param Path Configuration path or empty string.
   --  @return Validated settings.
   --  @exception Argument_Error The file is missing, malformed, unsupported, or outside configured ranges.

   type Loaded_Configuration is record
      Values                      : Settings;
      Source_Path                 : UString;
      Quality_Database_Configured : Boolean := False;
   end record;
   --  Validated settings plus non-semantic loading provenance.
   --  @field Values Effective semantic configuration.
   --  @field Source_Path Configuration file that supplied Values, or empty for defaults.
   --  @field Quality_Database_Configured Whether the file explicitly selected a quality database.

   function Load_With_Provenance (Path : String) return Loaded_Configuration;
   --  Load settings while retaining configuration-source metadata for adapters.
   --  @param Path Configuration path or empty string.
   --  @return Effective values and non-semantic loading provenance.
   --  @exception Argument_Error The file is missing, malformed, unsupported, or outside configured ranges.

   function Image (Item : Settings) return String;
   --  Return deterministic TOML-like terminal output with every effective setting.
   --  @param Item Settings to render.
   --  @return Stable configuration text.

   function Explain (Item : Loaded_Configuration) return String;
   --  Return every effective value together with its configuration provenance.
   --  @param Item Effective settings and their source file.
   --  @return Stable line-oriented value and source explanation.
end Improve.Config;

