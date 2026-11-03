with Ada.Strings.Unbounded;

--  Improve-owned configuration schema and validation.
package Improve.Config is
   --  Typed configuration schema, defaults, parsing, and deterministic rendering.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized configuration text.

   type Output_Format is (Terminal_Format, JSON_Format);
   --  User-visible output encoding.
   --  @enum Terminal_Format Human-readable terminal output.
   --  @enum JSON_Format Versioned JSON document.
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
   --  Return documented schema-version-1 defaults.
   --  @return Complete default settings.

   function Load (Path : String) return Settings;
   --  Load and validate a configuration file; an empty path returns defaults.
   --  @param Path Configuration path or empty string.
   --  @return Validated settings.
   --  @exception Argument_Error The file is missing, malformed, unsupported, or outside configured ranges.

   function Image (Item : Settings) return String;
   --  Return deterministic TOML-like terminal output with every effective setting.
   --  @param Item Settings to render.
   --  @return Stable configuration text.
end Improve.Config;

