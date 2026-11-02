with Ada.Strings.Unbounded;

--  Improve-owned configuration schema and validation.
package Improve.Config is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Output_Format is (Terminal_Format, JSON_Format);
   type Color_Mode is (Color_Auto, Color_Always, Color_Never);
   type Severity_Level is (Info, Low, Medium, High, Critical);
   type Selection_Mode is (Latest_Completed);
   type Publication_Mode is (Candidate_Publication);

   type Settings is record
      Quality_Database          : UString;
      Selection                 : Selection_Mode := Latest_Completed;
      Minimum_Severity          : Severity_Level := Low;
      Maximum_Tasks_Per_Plan    : Positive := 100;
      Maximum_Findings_Per_Task : Positive := 50;
      Allow_Investigation_Tasks : Boolean := True;
      Require_Review            : Boolean := True;
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

   function Defaults return Settings;
   --  Return documented schema-version-1 defaults.

   function Load (Path : String) return Settings;
   --  Load and validate a configuration file; an empty path returns defaults.
   --  @exception Argument_Error The file is missing, malformed, unsupported, or outside configured ranges.

   function Image (Item : Settings) return String;
   --  Return deterministic TOML-like terminal output with every effective setting.
end Improve.Config;

