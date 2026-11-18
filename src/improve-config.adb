with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Hostkit.Fs;
with Project_Tools.Files;
with Project_Tools.TOML;

package body Improve.Config is
   use Ada.Strings.Unbounded;
   use type Project_Tools.TOML.Boolean_Parse_Status;
   use type Project_Tools.TOML.Natural_Parse_Status;

   LF : constant Character := Character'Val (10);
   Maximum_Configuration_Bytes : constant := 1_048_576;

   type Setting_Value_Kind is (String_Value, Enum_Value, Positive_Value, Boolean_Value);
   type Setting_Id is
     (Schema_Version,
      Quality_Database, Quality_Selection, Maximum_Quality_Projects, Maximum_Quality_Runs,
      Maximum_Quality_Findings, Maximum_Quality_Database_Bytes,
      Maximum_Assessment_Findings, Maximum_Assessment_Bytes, Maximum_Normalized_Finding_Bytes,
      Maximum_Source_File_Bytes, Maximum_Source_Total_Bytes,
      Minimum_Severity, Maximum_Tasks_Per_Plan, Maximum_Findings_Per_Task,
      Allow_Investigation_Tasks, Require_Review, Agent_Max_Context_Bytes, Agent_Max_File_Bytes,
      Agent_Max_Response_Bytes, Agent_Timeout_Seconds,
      Maximum_Recovery_Operations, Maximum_History_Items, Maximum_Migration_Rows,
      Maximum_Persisted_Text_Bytes,
      Maximum_Persisted_Total_Bytes,
      Workflow_Task_Kind, Workflow_Publication, Require_Initialized_Project,
      Require_Fresh_Measurement, Require_Same_Policy, Require_Same_Toolchain,
      Require_No_New_Critical_Findings,
      Maximum_Output_Items, Output_Format_Setting, Output_Color);

   type Setting_Descriptor is record
      Section : UString;
      Name    : UString;
      Default : UString;
      Kind    : Setting_Value_Kind;
      Minimum : Natural := 0;
      Maximum : Natural := 0;
   end record;

   type Descriptor_Array is array (Setting_Id) of Setting_Descriptor;
   type Entry_Array is array (Setting_Id) of UString;
   type Presence_Array is array (Setting_Id) of Boolean;

   function Define
     (Section, Name, Default : String;
      Kind                   : Setting_Value_Kind;
      Minimum                : Natural := 0;
      Maximum                : Natural := 0) return Setting_Descriptor is
     ((To_Unbounded_String (Section), To_Unbounded_String (Name), To_Unbounded_String (Default),
       Kind, Minimum, Maximum));

   Definitions : constant Descriptor_Array :=
     [Define ("", "schema_version", "2", Positive_Value, 1, 2),
      Define ("quality", "database", ".ada-quality.db", String_Value),
      Define ("quality", "selection", "latest_completed", Enum_Value),
      Define ("quality", "maximum_database_projects", "10000", Positive_Value, 1, 100_000),
      Define ("quality", "maximum_database_runs", "1000000", Positive_Value, 1, 10_000_000),
      Define ("quality", "maximum_database_findings", "2000000", Positive_Value, 1, 10_000_000),
      Define ("quality", "maximum_database_bytes", "1073741824", Positive_Value, 1, 2_000_000_000),
      Define ("quality", "maximum_assessment_findings", "10000", Positive_Value, 1, 1_000_000),
      Define ("quality", "maximum_assessment_bytes", "16777216", Positive_Value, 1, 268_435_456),
      Define ("quality", "maximum_normalized_finding_bytes", "16777216", Positive_Value, 1, 268_435_456),
      Define ("quality", "maximum_source_file_bytes", "16777216", Positive_Value, 1, 1_073_741_824),
      Define ("quality", "maximum_source_total_bytes", "268435456", Positive_Value, 1, 2_000_000_000),
      Define ("planning", "minimum_severity", "low", Enum_Value),
      Define ("planning", "maximum_tasks_per_plan", "100", Positive_Value, 1, 10_000),
      Define ("planning", "maximum_findings_per_task", "50", Positive_Value, 1, 10_000),
      Define ("planning", "allow_investigation_tasks", "true", Boolean_Value),
      Define ("planning", "require_review", "true", Boolean_Value),
      Define ("planning", "agent_max_context_bytes", "131072", Positive_Value, 1_024, 10_485_760),
      Define ("planning", "agent_max_file_bytes", "32768", Positive_Value, 1, 10_485_760),
      Define ("planning", "agent_max_response_bytes", "131072", Positive_Value, 1, 1_048_576),
      Define ("planning", "agent_timeout_seconds", "60", Positive_Value, 1, 3_600),
      Define ("operations", "maximum_recovery_operations", "100", Positive_Value, 1, 10_000),
      Define ("operations", "maximum_history_items", "100000", Positive_Value, 1, 1_000_000),
      Define ("operations", "maximum_migration_rows", "1000000", Positive_Value, 1, 1_300_000_000),
      Define ("operations", "maximum_persisted_text_bytes", "1048576", Positive_Value, 1, 16_777_216),
      Define ("operations", "maximum_persisted_total_bytes", "67108864", Positive_Value, 1, 2_000_000_000),
      Define ("workflow", "task_kind", "auto", String_Value),
      Define ("workflow", "publication", "candidate", Enum_Value),
      Define ("workflow", "require_initialized_project", "true", Boolean_Value),
      Define ("verification", "require_fresh_measurement", "true", Boolean_Value),
      Define ("verification", "require_same_policy", "true", Boolean_Value),
      Define ("verification", "require_same_toolchain", "false", Boolean_Value),
      Define ("verification", "require_no_new_critical_findings", "true", Boolean_Value),
      Define ("output", "maximum_output_items", "10000", Positive_Value, 1, 100_000),
      Define ("output", "format", "terminal", Enum_Value),
      Define ("output", "color", "auto", Enum_Value)];

   package TOML_Codec is
      procedure Parse
        (Text    : String;
         Entries : out Entry_Array;
         Present : out Presence_Array);

      function String_Setting
        (Id      : Setting_Id;
         Entries : Entry_Array;
         Present : Presence_Array) return String;

      function Escape (Text : String) return String;
   end TOML_Codec;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Qualified (Id : Setting_Id) return String is
      Section : constant String := To_String (Definitions (Id).Section);
   begin
      return (if Section = "" then To_String (Definitions (Id).Name)
              else Section & "." & To_String (Definitions (Id).Name));
   end Qualified;

   function Known_Section (Name : String) return Boolean is
   begin
      for Definition of Definitions loop
         if Length (Definition.Section) > 0 and then To_String (Definition.Section) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Known_Section;

   function Setting_Of (Section, Name : String) return Setting_Id is
   begin
      for Id in Setting_Id loop
         if To_String (Definitions (Id).Section) = Section and then
           To_String (Definitions (Id).Name) = Name
         then
            return Id;
         end if;
      end loop;
      raise Argument_Error with
        "unknown or misplaced configuration setting: " &
        (if Section = "" then Name else Section & "." & Name);
   end Setting_Of;

   function Default_String (Id : Setting_Id) return String is
     (To_String (Definitions (Id).Default));

   function Default_Positive (Id : Setting_Id) return Positive is
     (Positive'Value (Default_String (Id)));

   function Default_Boolean (Id : Setting_Id) return Boolean is
     (Default_String (Id) = "true");

   package body TOML_Codec is separate;

   function Severity_Of (Value : String) return Severity_Level is
   begin
      if Value = "info" then return Info;
      elsif Value = "low" then return Low;
      elsif Value = "medium" then return Medium;
      elsif Value = "high" then return High;
      elsif Value = "critical" then return Critical;
      else raise Argument_Error with "planning.minimum_severity is invalid";
      end if;
   end Severity_Of;

   function Format_Of (Value : String) return Output_Format is
   begin
      if Value = "terminal" then return Terminal_Format;
      elsif Value = "json" then return JSON_Format;
      elsif Value = "markdown" then return Markdown_Format;
      else raise Argument_Error with "output.format must be terminal, json, or markdown";
      end if;
   end Format_Of;

   function Color_Of (Value : String) return Color_Mode is
   begin
      if Value = "auto" then return Color_Auto;
      elsif Value = "always" then return Color_Always;
      elsif Value = "never" then return Color_Never;
      else raise Argument_Error with "output.color must be auto, always, or never";
      end if;
   end Color_Of;

   procedure Validate_Operational_Text
     (Name           : String;
      Value          : String;
      Maximum_Length : Positive) is
   begin
      if Value = "" then
         raise Argument_Error with Name & " must not be empty";
      elsif Value'Length > Maximum_Length then
         raise Argument_Error with Name & " exceeds its maximum length";
      end if;
      for Item of Value loop
         if Character'Pos (Item) < 32 or else Character'Pos (Item) = 127 then
            raise Argument_Error with Name & " contains a control character";
         end if;
      end loop;
   end Validate_Operational_Text;

   function Read_Configuration (Path : String) return String is
      Full    : constant String := Ada.Directories.Full_Name (Path);
      Root    : constant String := Ada.Directories.Containing_Directory (Full);
      Name    : constant String := Ada.Directories.Simple_Name (Full);
      Text    : UString;
      Outcome : Hostkit.Fs.Read_Beneath_Outcome;
   begin
      Hostkit.Fs.Read_Beneath (Root, Name, Maximum_Configuration_Bytes, Text, Outcome);
      case Outcome is
         when Hostkit.Fs.Read_Done => return To_String (Text);
         when Hostkit.Fs.Read_Too_Large =>
            raise Argument_Error with "configuration file exceeds 1048576 bytes";
         when Hostkit.Fs.Read_Outside =>
            raise Argument_Error with "configuration path contains an unsafe symbolic link";
         when others =>
            raise Argument_Error with "configuration file cannot be read: " & Path;
      end case;
   end Read_Configuration;

   function Defaults return Settings is
     ((Quality_Database          => To_Unbounded_String (Default_String (Quality_Database)),
       Selection                 => Latest_Completed,
       Maximum_Quality_Projects  => Default_Positive (Maximum_Quality_Projects),
       Maximum_Quality_Runs      => Default_Positive (Maximum_Quality_Runs),
       Maximum_Quality_Findings  => Default_Positive (Maximum_Quality_Findings),
       Maximum_Quality_Database_Bytes => Default_Positive (Maximum_Quality_Database_Bytes),
       Maximum_Assessment_Findings => Default_Positive (Maximum_Assessment_Findings),
       Maximum_Assessment_Bytes  => Default_Positive (Maximum_Assessment_Bytes),
       Maximum_Normalized_Finding_Bytes => Default_Positive (Maximum_Normalized_Finding_Bytes),
       Maximum_Source_File_Bytes => Default_Positive (Maximum_Source_File_Bytes),
       Maximum_Source_Total_Bytes => Default_Positive (Maximum_Source_Total_Bytes),
       Minimum_Severity          => Severity_Of (Default_String (Minimum_Severity)),
       Maximum_Tasks_Per_Plan    => Default_Positive (Maximum_Tasks_Per_Plan),
       Maximum_Findings_Per_Task => Default_Positive (Maximum_Findings_Per_Task),
       Allow_Investigation_Tasks => Default_Boolean (Allow_Investigation_Tasks),
       Require_Review            => Default_Boolean (Require_Review),
       Agent_Max_Context_Bytes   => Default_Positive (Agent_Max_Context_Bytes),
       Agent_Max_File_Bytes      => Default_Positive (Agent_Max_File_Bytes),
       Agent_Max_Response_Bytes  => Default_Positive (Agent_Max_Response_Bytes),
       Agent_Timeout_Seconds     => Default_Positive (Agent_Timeout_Seconds),
       Maximum_Output_Items      => Default_Positive (Maximum_Output_Items),
       Maximum_History_Items     => Default_Positive (Maximum_History_Items),
       Maximum_Migration_Rows    => Default_Positive (Maximum_Migration_Rows),
       Maximum_Persisted_Text_Bytes => Default_Positive (Maximum_Persisted_Text_Bytes),
       Maximum_Persisted_Total_Bytes => Default_Positive (Maximum_Persisted_Total_Bytes),
       Maximum_Recovery_Operations => Default_Positive (Maximum_Recovery_Operations),
       Task_Kind                 => To_Unbounded_String (Default_String (Workflow_Task_Kind)),
       Publication               => Candidate_Publication,
       Require_Initialized       => Default_Boolean (Require_Initialized_Project),
       Require_Fresh_Measurement => Default_Boolean (Require_Fresh_Measurement),
       Require_Same_Policy       => Default_Boolean (Require_Same_Policy),
       Require_Same_Toolchain    => Default_Boolean (Require_Same_Toolchain),
       Require_No_New_Critical   => Default_Boolean (Require_No_New_Critical_Findings),
       Format                    => Format_Of (Default_String (Output_Format_Setting)),
       Color                     => Color_Of (Default_String (Output_Color))));

   function Quality_Severity (Value : Severity_Level) return Ada_Quality.Types.Severity is
     (case Value is
         when Info => Ada_Quality.Types.Info,
         when Low => Ada_Quality.Types.Low,
         when Medium => Ada_Quality.Types.Medium,
         when High => Ada_Quality.Types.High,
         when Critical => Ada_Quality.Types.Critical);

   function Load_With_Provenance (Path : String) return Loaded_Configuration is
      Result : Settings := Defaults;
   begin
      if Path = "" then
         return
           (Values => Result, Source_Path => Null_Unbounded_String,
            Quality_Database_Configured => False);
      elsif not Project_Tools.Files.File_Exists (Path) then
         raise Argument_Error with "configuration file not found: " & Path;
      end if;
      declare
         Text : constant String := Read_Configuration (Path);
         Entries : Entry_Array;
         Present : Presence_Array := [others => False];
         Version : Positive;

         function Line_Of (Id : Setting_Id) return String is
           (if Present (Id) then To_String (Entries (Id)) else "");

         function String_Setting (Id : Setting_Id) return String is
           (TOML_Codec.String_Setting (Id, Entries, Present));

         function Positive_Setting (Id : Setting_Id) return Positive is
            Line   : constant String := Line_Of (Id);
            Name   : constant String := To_String (Definitions (Id).Name);
            Parsed : constant Project_Tools.TOML.Natural_Parse_Result :=
              (if Line = "" then (Status => Project_Tools.TOML.Missing_Natural, Value => 0)
               else Project_Tools.TOML.Parse_Natural_After (Line, Name, Line'First));
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_Natural or else
              (Parsed.Status = Project_Tools.TOML.Parsed_Natural and then Parsed.Value = 0)
            then
               raise Argument_Error with "setting " & Qualified (Id) & " must be a positive integer";
            elsif Parsed.Status = Project_Tools.TOML.Missing_Natural then
               return Default_Positive (Id);
            elsif Parsed.Value < Definitions (Id).Minimum or else Parsed.Value > Definitions (Id).Maximum then
               raise Argument_Error with
                 "setting " & Qualified (Id) & " must be between" &
                 Natural'Image (Definitions (Id).Minimum) & " and" & Natural'Image (Definitions (Id).Maximum);
            end if;
            return Parsed.Value;
         end Positive_Setting;

         function Boolean_Setting (Id : Setting_Id) return Boolean is
            Line   : constant String := Line_Of (Id);
            Name   : constant String := To_String (Definitions (Id).Name);
            Parsed : constant Project_Tools.TOML.Boolean_Parse_Result :=
              (if Line = "" then (Status => Project_Tools.TOML.Missing_Boolean, Value => False)
               else Project_Tools.TOML.Parse_Boolean_After (Line, Name, Line'First));
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_Boolean then
               raise Argument_Error with "malformed boolean setting: " & Qualified (Id);
            elsif Parsed.Status = Project_Tools.TOML.Missing_Boolean then
               return Default_Boolean (Id);
            end if;
            return Parsed.Value;
         end Boolean_Setting;

         procedure Apply (Id : Setting_Id) is
         begin
            case Id is
               when Schema_Version | Quality_Selection | Workflow_Publication => null;
               when Quality_Database =>
                  Result.Quality_Database := To_Unbounded_String (String_Setting (Id));
               when Maximum_Quality_Projects =>
                  Result.Maximum_Quality_Projects := Positive_Setting (Id);
               when Maximum_Quality_Runs =>
                  Result.Maximum_Quality_Runs := Positive_Setting (Id);
               when Maximum_Quality_Findings =>
                  Result.Maximum_Quality_Findings := Positive_Setting (Id);
               when Maximum_Quality_Database_Bytes =>
                  Result.Maximum_Quality_Database_Bytes := Positive_Setting (Id);
               when Maximum_Assessment_Findings =>
                  Result.Maximum_Assessment_Findings := Positive_Setting (Id);
               when Maximum_Assessment_Bytes =>
                  Result.Maximum_Assessment_Bytes := Positive_Setting (Id);
               when Maximum_Normalized_Finding_Bytes =>
                  Result.Maximum_Normalized_Finding_Bytes := Positive_Setting (Id);
               when Maximum_Source_File_Bytes =>
                  Result.Maximum_Source_File_Bytes := Positive_Setting (Id);
               when Maximum_Source_Total_Bytes =>
                  Result.Maximum_Source_Total_Bytes := Positive_Setting (Id);
               when Minimum_Severity =>
                  Result.Minimum_Severity := Severity_Of (String_Setting (Id));
               when Maximum_Tasks_Per_Plan =>
                  Result.Maximum_Tasks_Per_Plan := Positive_Setting (Id);
               when Maximum_Findings_Per_Task =>
                  Result.Maximum_Findings_Per_Task := Positive_Setting (Id);
               when Allow_Investigation_Tasks =>
                  Result.Allow_Investigation_Tasks := Boolean_Setting (Id);
               when Require_Review =>
                  Result.Require_Review := Boolean_Setting (Id);
               when Agent_Max_Context_Bytes =>
                  Result.Agent_Max_Context_Bytes := Positive_Setting (Id);
               when Agent_Max_File_Bytes =>
                  Result.Agent_Max_File_Bytes := Positive_Setting (Id);
               when Agent_Max_Response_Bytes =>
                  Result.Agent_Max_Response_Bytes := Positive_Setting (Id);
               when Agent_Timeout_Seconds =>
                  Result.Agent_Timeout_Seconds := Positive_Setting (Id);
               when Maximum_Recovery_Operations =>
                  Result.Maximum_Recovery_Operations := Positive_Setting (Id);
               when Maximum_History_Items =>
                  Result.Maximum_History_Items := Positive_Setting (Id);
               when Maximum_Migration_Rows =>
                  Result.Maximum_Migration_Rows := Positive_Setting (Id);
               when Maximum_Persisted_Text_Bytes =>
                  Result.Maximum_Persisted_Text_Bytes := Positive_Setting (Id);
               when Maximum_Persisted_Total_Bytes =>
                  Result.Maximum_Persisted_Total_Bytes := Positive_Setting (Id);
               when Workflow_Task_Kind =>
                  Result.Task_Kind := To_Unbounded_String (String_Setting (Id));
               when Require_Initialized_Project =>
                  Result.Require_Initialized := Boolean_Setting (Id);
               when Require_Fresh_Measurement =>
                  Result.Require_Fresh_Measurement := Boolean_Setting (Id);
               when Require_Same_Policy =>
                  Result.Require_Same_Policy := Boolean_Setting (Id);
               when Require_Same_Toolchain =>
                  Result.Require_Same_Toolchain := Boolean_Setting (Id);
               when Require_No_New_Critical_Findings =>
                  Result.Require_No_New_Critical := Boolean_Setting (Id);
               when Maximum_Output_Items =>
                  Result.Maximum_Output_Items := Positive_Setting (Id);
               when Output_Format_Setting =>
                  Result.Format := Format_Of (String_Setting (Id));
               when Output_Color =>
                  Result.Color := Color_Of (String_Setting (Id));
            end case;
         end Apply;

      begin
         TOML_Codec.Parse (Text, Entries, Present);
         if not Present (Schema_Version) then
            raise Argument_Error with "configuration schema_version is required";
         end if;
         Version := Positive_Setting (Schema_Version);
         if Version not in 1 | 2 then
            raise Argument_Error with "configuration schema_version must be 1 or 2";
         elsif Version = 1 and then
           (Present (Maximum_Normalized_Finding_Bytes) or else
            Present (Maximum_Source_File_Bytes) or else Present (Maximum_Source_Total_Bytes) or else
            Present (Maximum_Migration_Rows) or else Present (Maximum_Persisted_Total_Bytes))
         then
            raise Argument_Error with "new bounded-evidence settings require configuration schema_version 2";
         elsif String_Setting (Quality_Selection) /= "latest_completed" then
            raise Argument_Error with "quality.selection must be latest_completed";
         elsif String_Setting (Workflow_Publication) /= "candidate" then
            raise Argument_Error with "workflow.publication must be candidate";
         end if;

         for Id in Setting_Id loop
            Apply (Id);
         end loop;
         Validate_Operational_Text
           ("quality.database", To_String (Result.Quality_Database), Maximum_Length => 4_096);
         if Result.Maximum_Source_File_Bytes > Result.Maximum_Source_Total_Bytes then
            raise Argument_Error with "quality.maximum_source_file_bytes exceeds the total source limit";
         end if;
         if Result.Agent_Max_File_Bytes > Result.Agent_Max_Context_Bytes then
            raise Argument_Error with "planning.agent_max_file_bytes exceeds the context limit";
         end if;
         Validate_Operational_Text ("workflow.task_kind", To_String (Result.Task_Kind), Maximum_Length => 128);
         if not Result.Require_Initialized then
            raise Argument_Error with "workflow.require_initialized_project must be true";
         end if;
         return
           (Values => Result, Source_Path => To_Unbounded_String (Path),
            Quality_Database_Configured => Present (Quality_Database));
      end;
   end Load_With_Provenance;

   function Load (Path : String) return Settings is
     (Load_With_Provenance (Path).Values);

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Raw_Value (Item : Settings; Id : Setting_Id) return String is
   begin
      case Id is
         when Schema_Version => return "2";
         when Quality_Database => return To_String (Item.Quality_Database);
         when Quality_Selection => return "latest_completed";
         when Maximum_Quality_Projects => return Number (Item.Maximum_Quality_Projects);
         when Maximum_Quality_Runs => return Number (Item.Maximum_Quality_Runs);
         when Maximum_Quality_Findings => return Number (Item.Maximum_Quality_Findings);
         when Maximum_Quality_Database_Bytes => return Number (Item.Maximum_Quality_Database_Bytes);
         when Maximum_Assessment_Findings => return Number (Item.Maximum_Assessment_Findings);
         when Maximum_Assessment_Bytes => return Number (Item.Maximum_Assessment_Bytes);
         when Maximum_Normalized_Finding_Bytes => return Number (Item.Maximum_Normalized_Finding_Bytes);
         when Maximum_Source_File_Bytes => return Number (Item.Maximum_Source_File_Bytes);
         when Maximum_Source_Total_Bytes => return Number (Item.Maximum_Source_Total_Bytes);
         when Minimum_Severity =>
            return Ada.Characters.Handling.To_Lower (Severity_Level'Image (Item.Minimum_Severity));
         when Maximum_Tasks_Per_Plan => return Number (Item.Maximum_Tasks_Per_Plan);
         when Maximum_Findings_Per_Task => return Number (Item.Maximum_Findings_Per_Task);
         when Allow_Investigation_Tasks => return Boolean_Image (Item.Allow_Investigation_Tasks);
         when Require_Review => return Boolean_Image (Item.Require_Review);
         when Agent_Max_Context_Bytes => return Number (Item.Agent_Max_Context_Bytes);
         when Agent_Max_File_Bytes => return Number (Item.Agent_Max_File_Bytes);
         when Agent_Max_Response_Bytes => return Number (Item.Agent_Max_Response_Bytes);
         when Agent_Timeout_Seconds => return Number (Item.Agent_Timeout_Seconds);
         when Maximum_Recovery_Operations => return Number (Item.Maximum_Recovery_Operations);
         when Maximum_History_Items => return Number (Item.Maximum_History_Items);
         when Maximum_Migration_Rows => return Number (Item.Maximum_Migration_Rows);
         when Maximum_Persisted_Text_Bytes => return Number (Item.Maximum_Persisted_Text_Bytes);
         when Maximum_Persisted_Total_Bytes => return Number (Item.Maximum_Persisted_Total_Bytes);
         when Workflow_Task_Kind => return To_String (Item.Task_Kind);
         when Workflow_Publication => return "candidate";
         when Require_Initialized_Project => return Boolean_Image (Item.Require_Initialized);
         when Require_Fresh_Measurement => return Boolean_Image (Item.Require_Fresh_Measurement);
         when Require_Same_Policy => return Boolean_Image (Item.Require_Same_Policy);
         when Require_Same_Toolchain => return Boolean_Image (Item.Require_Same_Toolchain);
         when Require_No_New_Critical_Findings => return Boolean_Image (Item.Require_No_New_Critical);
         when Maximum_Output_Items => return Number (Item.Maximum_Output_Items);
         when Output_Format_Setting =>
            return
              (case Item.Format is
                  when Terminal_Format => "terminal",
                  when JSON_Format => "json",
                  when Markdown_Format => "markdown");
         when Output_Color =>
            return
              (case Item.Color is
                  when Color_Auto => "auto",
                  when Color_Always => "always",
                  when Color_Never => "never");
      end case;
   end Raw_Value;

   function Image (Item : Settings) return String is
      Result       : UString;
      Last_Section : UString;
   begin
      Validate_Operational_Text
        ("quality.database", To_String (Item.Quality_Database), Maximum_Length => 4_096);
      Validate_Operational_Text ("workflow.task_kind", To_String (Item.Task_Kind), Maximum_Length => 128);
      for Id in Setting_Id loop
         declare
            Definition : Setting_Descriptor renames Definitions (Id);
            Section    : constant String := To_String (Definition.Section);
            Raw        : constant String := Raw_Value (Item, Id);
            Rendered   : constant String :=
              (if Definition.Kind in String_Value | Enum_Value then '"' & TOML_Codec.Escape (Raw) & '"' else Raw);
         begin
            if Section /= To_String (Last_Section) then
               Append (Result, "[" & Section & "]" & LF);
               Last_Section := Definition.Section;
            end if;
            Append (Result, To_String (Definition.Name) & " = " & Rendered & LF);
         end;
      end loop;
      return To_String (Result);
   end Image;

   function Evidence_Limits_Of (Item : Settings) return Evidence_Limits is
     ((Database_Bytes           => Item.Maximum_Quality_Database_Bytes,
       Assessment_Bytes         => Item.Maximum_Assessment_Bytes,
       Normalized_Finding_Bytes => Item.Maximum_Normalized_Finding_Bytes,
       Source_File_Bytes        => Item.Maximum_Source_File_Bytes,
       Source_Total_Bytes       => Item.Maximum_Source_Total_Bytes));
end Improve.Config;
