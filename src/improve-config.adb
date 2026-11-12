with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Hostkit.Fs;
with Project_Tools.Files;
with Project_Tools.TOML;

package body Improve.Config is
   use Ada.Strings.Unbounded;
   use type Project_Tools.TOML.Boolean_Parse_Status;
   use type Project_Tools.TOML.Natural_Parse_Status;
   use type Project_Tools.TOML.String_Parse_Status;

   LF : constant Character := Character'Val (10);
   Maximum_Configuration_Bytes : constant := 1_048_576;

   function Read_Configuration (Path : String) return String is
      Full    : constant String := Ada.Directories.Full_Name (Path);
      Root    : constant String := Ada.Directories.Containing_Directory (Full);
      Name    : constant String := Ada.Directories.Simple_Name (Full);
      Text    : Unbounded_String;
      Outcome : Hostkit.Fs.Read_Beneath_Outcome;
   begin
      Hostkit.Fs.Read_Beneath (Root, Name, Maximum_Configuration_Bytes, Text, Outcome);
      case Outcome is
         when Hostkit.Fs.Read_Done =>
            return To_String (Text);
         when Hostkit.Fs.Read_Too_Large =>
            raise Argument_Error with "configuration file exceeds 1048576 bytes";
         when Hostkit.Fs.Read_Outside =>
            raise Argument_Error with "configuration path contains an unsafe symbolic link";
         when others =>
            raise Argument_Error with "configuration file cannot be read: " & Path;
      end case;
   end Read_Configuration;

   function Known_Section (Name : String) return Boolean is
     (Name in "quality" | "planning" | "operations" | "workflow" | "verification" | "output");

   function Allowed_Key (Section, Key : String) return Boolean is
   begin
      if Section = "" then
         return Key = "schema_version";
      elsif Section = "quality" then
         return Key in "database" | "selection" | "maximum_database_projects" |
           "maximum_database_runs" | "maximum_database_findings" |
           "maximum_assessment_findings" | "maximum_assessment_bytes";
      elsif Section = "planning" then
         return Key in "minimum_severity" | "maximum_tasks_per_plan" |
           "maximum_findings_per_task" | "allow_investigation_tasks" | "require_review" |
           "agent_max_context_bytes" | "agent_max_file_bytes" | "agent_max_response_bytes" |
           "agent_timeout_seconds";
      elsif Section = "operations" then
         return Key in "maximum_recovery_operations" | "maximum_history_items" |
           "maximum_persisted_text_bytes";
      elsif Section = "workflow" then
         return Key in "task_kind" | "publication" | "require_initialized_project";
      elsif Section = "verification" then
         return Key in "require_fresh_measurement" | "require_same_policy" |
           "require_same_toolchain" | "require_no_new_critical_findings";
      elsif Section = "output" then
         return Key in "format" | "color" | "maximum_output_items";
      end if;
      return False;
   end Allowed_Key;

   function Defaults return Settings is
     ((Quality_Database          => To_Unbounded_String (".ada-quality.db"),
       Selection                 => Latest_Completed,
       Maximum_Quality_Projects  => 10_000,
       Maximum_Quality_Runs      => 1_000_000,
       Maximum_Quality_Findings  => 2_000_000,
       Maximum_Assessment_Findings => 10_000,
       Maximum_Assessment_Bytes  => 16_777_216,
       Minimum_Severity          => Low,
       Maximum_Tasks_Per_Plan    => 100,
       Maximum_Findings_Per_Task => 50,
       Allow_Investigation_Tasks => True,
       Require_Review            => True,
       Agent_Max_Context_Bytes   => 131_072,
       Agent_Max_File_Bytes      => 32_768,
       Agent_Max_Response_Bytes  => 131_072,
       Agent_Timeout_Seconds     => 60,
       Maximum_Output_Items      => 10_000,
       Maximum_History_Items     => 100_000,
       Maximum_Persisted_Text_Bytes => 1_048_576,
       Maximum_Recovery_Operations => 100,
       Task_Kind                 => To_Unbounded_String ("auto"),
       Publication               => Candidate_Publication,
       Require_Initialized       => True,
       Require_Fresh_Measurement => True,
       Require_Same_Policy       => True,
       Require_Same_Toolchain    => False,
       Require_No_New_Critical   => True,
       Format                    => Terminal_Format,
       Color                     => Color_Auto));

   function Quality_Severity (Value : Severity_Level) return Ada_Quality.Types.Severity is
     (case Value is
         when Info => Ada_Quality.Types.Info,
         when Low => Ada_Quality.Types.Low,
         when Medium => Ada_Quality.Types.Medium,
         when High => Ada_Quality.Types.High,
         when Critical => Ada_Quality.Types.Critical);

   function Load (Path : String) return Settings is
      Result : Settings := Defaults;
   begin
      if Path = "" then
         return Result;
      elsif not Project_Tools.Files.File_Exists (Path) then
         raise Argument_Error with "configuration file not found: " & Path;
      end if;
      declare
         Text : constant String := Read_Configuration (Path);

         package Entry_Maps is new Ada.Containers.Indefinite_Hashed_Maps
           (Key_Type        => String,
            Element_Type    => Unbounded_String,
            Hash            => Ada.Strings.Hash,
            Equivalent_Keys => "=");

         Entries : Entry_Maps.Map;

         function Qualified (Section, Key : String) return String is
           ((if Section = "" then Key else Section & "." & Key));

         procedure Validate_Document is
            Current_Section : Unbounded_String;
            Start           : Natural := Text'First;
         begin
            while Start <= Text'Last loop
               declare
                  Stop : Natural := Start;
               begin
                  while Stop <= Text'Last and then Text (Stop) /= LF loop
                     Stop := Stop + 1;
                  end loop;
                  declare
                     Last : Natural := Stop - 1;
                  begin
                     if Last >= Start and then Text (Last) = Character'Val (13) then
                        Last := Last - 1;
                     end if;
                     declare
                        Line : constant String :=
                          (if Last < Start then ""
                           else Ada.Strings.Fixed.Trim (Text (Start .. Last), Ada.Strings.Both));
                     begin
                        if Line = "" or else Line (Line'First) = '#' then
                           null;
                        elsif Line (Line'First) = '[' then
                           declare Close : constant Natural := Ada.Strings.Fixed.Index (Line, "]"); begin
                              if Line'Length < 3 or else Close = 0 or else Line (Line'First + 1) = '[' then
                                 raise Argument_Error with "malformed configuration section";
                              end if;
                              declare
                                 Rest : constant String :=
                                   Ada.Strings.Fixed.Trim (Line (Close + 1 .. Line'Last), Ada.Strings.Both);
                                 Name : constant String := Line (Line'First + 1 .. Close - 1);
                              begin
                                 if Rest /= "" and then Rest (Rest'First) /= '#' then
                                    raise Argument_Error with "malformed configuration section";
                                 end if;
                                 if not Known_Section (Name) then
                                    raise Argument_Error with "unknown configuration section: " & Name;
                                 end if;
                                 Current_Section := To_Unbounded_String (Name);
                              end;
                           end;
                        else
                           declare Equals : constant Natural := Ada.Strings.Fixed.Index (Line, "="); begin
                              if Equals = 0 then
                                 raise Argument_Error with "malformed configuration entry";
                              end if;
                              declare
                                 Key : constant String :=
                                   Ada.Strings.Fixed.Trim (Line (Line'First .. Equals - 1), Ada.Strings.Both);
                                 Section : constant String := To_String (Current_Section);
                                 Name : constant String := Qualified (Section, Key);
                              begin
                                 if not Allowed_Key (Section, Key) then
                                    raise Argument_Error with "unknown or misplaced configuration setting: " & Name;
                                 elsif Entries.Contains (Name) then
                                    raise Argument_Error with "duplicate configuration setting: " & Name;
                                 end if;
                                 Entries.Insert (Name, To_Unbounded_String (Line));
                              end;
                           end;
                        end if;
                     end;
                  end;
                  Start := Stop + 1;
               end;
            end loop;
         end Validate_Document;

         function Line_Of (Section, Key : String) return String is
            Name : constant String := Qualified (Section, Key);
         begin
            return (if Entries.Contains (Name) then To_String (Entries.Element (Name)) else "");
         end Line_Of;

         function String_Value (Section, Key : String; Default : String) return String is
            Line : constant String := Line_Of (Section, Key);
            Parsed : constant Project_Tools.TOML.String_Parse_Result :=
              (if Line = "" then
                  (Status => Project_Tools.TOML.Missing_String, Value => Null_Unbounded_String)
               else Project_Tools.TOML.Parse_String_After (Line, Key, Line'First));
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_String then
               raise Argument_Error with "malformed string setting: " & Key;
            elsif Parsed.Status = Project_Tools.TOML.Missing_String then
               return Default;
            end if;
            return To_String (Parsed.Value);
         end String_Value;

         function Natural_Value (Section, Key : String; Default : Positive) return Positive is
            Line : constant String := Line_Of (Section, Key);
            Parsed : constant Project_Tools.TOML.Natural_Parse_Result :=
              (if Line = "" then (Status => Project_Tools.TOML.Missing_Natural, Value => 0)
               else Project_Tools.TOML.Parse_Natural_After (Line, Key, Line'First));
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_Natural or else
              (Parsed.Status = Project_Tools.TOML.Parsed_Natural and then Parsed.Value = 0)
            then
               raise Argument_Error with "setting " & Key & " must be a positive integer";
            elsif Parsed.Status = Project_Tools.TOML.Missing_Natural then
               return Default;
            end if;
            return Parsed.Value;
         end Natural_Value;

         function Boolean_Value (Section, Key : String; Default : Boolean) return Boolean is
            Line : constant String := Line_Of (Section, Key);
            Parsed : constant Project_Tools.TOML.Boolean_Parse_Result :=
              (if Line = "" then (Status => Project_Tools.TOML.Missing_Boolean, Value => False)
               else Project_Tools.TOML.Parse_Boolean_After (Line, Key, Line'First));
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_Boolean then
               raise Argument_Error with "malformed boolean setting: " & Key;
            elsif Parsed.Status = Project_Tools.TOML.Missing_Boolean then
               return Default;
            end if;
            return Parsed.Value;
         end Boolean_Value;

      begin
         Validate_Document;
         declare
            Schema_Line : constant String := Line_Of ("", "schema_version");
            Schema : constant Project_Tools.TOML.Natural_Parse_Result :=
              (if Schema_Line = "" then (Status => Project_Tools.TOML.Missing_Natural, Value => 0)
               else Project_Tools.TOML.Parse_Natural_After
                 (Schema_Line, "schema_version", Schema_Line'First));
            Selection : constant String := String_Value ("quality", "selection", "latest_completed");
            Severity  : constant String := String_Value ("planning", "minimum_severity", "low");
            Kind      : constant String := String_Value ("workflow", "task_kind", "auto");
            Publish   : constant String := String_Value ("workflow", "publication", "candidate");
            Format    : constant String := String_Value ("output", "format", "terminal");
            Color     : constant String := String_Value ("output", "color", "auto");
         begin
         if Schema.Status /= Project_Tools.TOML.Parsed_Natural or else Schema.Value /= 1 then
            raise Argument_Error with "configuration schema_version must be 1";
         elsif Selection /= "latest_completed" then
            raise Argument_Error with "quality.selection must be latest_completed";
         elsif Kind = "" then
            raise Argument_Error with "workflow.task_kind must not be empty";
         elsif Publish /= "candidate" then
            raise Argument_Error with "workflow.publication must be candidate";
         end if;
         Result.Quality_Database :=
           To_Unbounded_String (String_Value ("quality", "database", ".ada-quality.db"));
         if Length (Result.Quality_Database) = 0 then
            raise Argument_Error with "quality.database must not be empty";
         end if;
         Result.Maximum_Quality_Projects := Natural_Value ("quality", "maximum_database_projects", 10_000);
         Result.Maximum_Quality_Runs := Natural_Value ("quality", "maximum_database_runs", 1_000_000);
         Result.Maximum_Quality_Findings := Natural_Value ("quality", "maximum_database_findings", 2_000_000);
         Result.Maximum_Assessment_Findings :=
           Natural_Value ("quality", "maximum_assessment_findings", 10_000);
         Result.Maximum_Assessment_Bytes := Natural_Value ("quality", "maximum_assessment_bytes", 16_777_216);
         if Result.Maximum_Quality_Projects > 100_000 then
            raise Argument_Error with "quality.maximum_database_projects exceeds 100000";
         elsif Result.Maximum_Quality_Runs > 10_000_000 then
            raise Argument_Error with "quality.maximum_database_runs exceeds 10000000";
         elsif Result.Maximum_Quality_Findings > 10_000_000 then
            raise Argument_Error with "quality.maximum_database_findings exceeds 10000000";
         end if;
         if Result.Maximum_Assessment_Findings > 1_000_000 then
            raise Argument_Error with "quality.maximum_assessment_findings exceeds 1000000";
         elsif Result.Maximum_Assessment_Bytes > 268_435_456 then
            raise Argument_Error with "quality.maximum_assessment_bytes exceeds 268435456";
         end if;
         if Severity = "info" then Result.Minimum_Severity := Info;
         elsif Severity = "low" then Result.Minimum_Severity := Low;
         elsif Severity = "medium" then Result.Minimum_Severity := Medium;
         elsif Severity = "high" then Result.Minimum_Severity := High;
         elsif Severity = "critical" then Result.Minimum_Severity := Critical;
         else raise Argument_Error with "planning.minimum_severity is invalid";
         end if;
         Result.Maximum_Tasks_Per_Plan := Natural_Value ("planning", "maximum_tasks_per_plan", 100);
         Result.Maximum_Findings_Per_Task := Natural_Value ("planning", "maximum_findings_per_task", 50);
         if Result.Maximum_Tasks_Per_Plan > 10_000 then
            raise Argument_Error with "planning.maximum_tasks_per_plan exceeds 10000";
         elsif Result.Maximum_Findings_Per_Task > 10_000 then
            raise Argument_Error with "planning.maximum_findings_per_task exceeds 10000";
         end if;
         Result.Allow_Investigation_Tasks :=
           Boolean_Value ("planning", "allow_investigation_tasks", True);
         Result.Require_Review := Boolean_Value ("planning", "require_review", True);
         Result.Agent_Max_Context_Bytes := Natural_Value ("planning", "agent_max_context_bytes", 131_072);
         Result.Agent_Max_File_Bytes := Natural_Value ("planning", "agent_max_file_bytes", 32_768);
         Result.Agent_Max_Response_Bytes := Natural_Value ("planning", "agent_max_response_bytes", 131_072);
         Result.Agent_Timeout_Seconds := Natural_Value ("planning", "agent_timeout_seconds", 60);
         Result.Maximum_Output_Items := Natural_Value ("output", "maximum_output_items", 10_000);
         Result.Maximum_History_Items := Natural_Value ("operations", "maximum_history_items", 100_000);
         Result.Maximum_Persisted_Text_Bytes :=
           Natural_Value ("operations", "maximum_persisted_text_bytes", 1_048_576);
         Result.Maximum_Recovery_Operations :=
           Natural_Value ("operations", "maximum_recovery_operations", 100);
         if Result.Agent_Max_Context_Bytes < 1_024 or else Result.Agent_Max_Context_Bytes > 10_485_760 then
            raise Argument_Error with "planning.agent_max_context_bytes must be between 1024 and 10485760";
         elsif Result.Agent_Max_File_Bytes > Result.Agent_Max_Context_Bytes then
            raise Argument_Error with "planning.agent_max_file_bytes exceeds the context limit";
         elsif Result.Agent_Max_Response_Bytes > 1_048_576 then
            raise Argument_Error with "planning.agent_max_response_bytes exceeds 1048576";
         elsif Result.Agent_Timeout_Seconds > 3_600 then
            raise Argument_Error with "planning.agent_timeout_seconds exceeds 3600";
         elsif Result.Maximum_Output_Items > 100_000 then
            raise Argument_Error with "output.maximum_output_items exceeds 100000";
         elsif Result.Maximum_History_Items > 1_000_000 then
            raise Argument_Error with "operations.maximum_history_items exceeds 1000000";
         elsif Result.Maximum_Persisted_Text_Bytes > 16_777_216 then
            raise Argument_Error with "operations.maximum_persisted_text_bytes exceeds 16777216";
         elsif Result.Maximum_Recovery_Operations > 10_000 then
            raise Argument_Error with "operations.maximum_recovery_operations exceeds 10000";
         end if;
         Result.Task_Kind := To_Unbounded_String (Kind);
         Result.Require_Initialized := Boolean_Value ("workflow", "require_initialized_project", True);
         if not Result.Require_Initialized then
            raise Argument_Error with "workflow.require_initialized_project must be true";
         end if;
         Result.Require_Fresh_Measurement :=
           Boolean_Value ("verification", "require_fresh_measurement", True);
         Result.Require_Same_Policy := Boolean_Value ("verification", "require_same_policy", True);
         Result.Require_Same_Toolchain := Boolean_Value ("verification", "require_same_toolchain", False);
         Result.Require_No_New_Critical :=
           Boolean_Value ("verification", "require_no_new_critical_findings", True);
         if Format = "terminal" then Result.Format := Terminal_Format;
         elsif Format = "json" then Result.Format := JSON_Format;
         else raise Argument_Error with "output.format must be terminal or json";
         end if;
         if Color = "auto" then Result.Color := Color_Auto;
         elsif Color = "always" then Result.Color := Color_Always;
         elsif Color = "never" then Result.Color := Color_Never;
         else raise Argument_Error with "output.color must be auto, always, or never";
         end if;
         end;
      end;
      return Result;
   end Load;

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Image (Item : Settings) return String is
      function Lower (Text : String) return String is (Ada.Characters.Handling.To_Lower (Text));
   begin
      return
        "schema_version = 1" & LF &
        "[quality]" & LF &
        "database = """ & To_String (Item.Quality_Database) & """" & LF &
        "selection = ""latest_completed""" & LF &
        "maximum_database_projects =" & Positive'Image (Item.Maximum_Quality_Projects) & LF &
        "maximum_database_runs =" & Positive'Image (Item.Maximum_Quality_Runs) & LF &
        "maximum_database_findings =" & Positive'Image (Item.Maximum_Quality_Findings) & LF &
        "maximum_assessment_findings =" & Positive'Image (Item.Maximum_Assessment_Findings) & LF &
        "maximum_assessment_bytes =" & Positive'Image (Item.Maximum_Assessment_Bytes) & LF &
        "[planning]" & LF &
        "minimum_severity = """ & Lower (Severity_Level'Image (Item.Minimum_Severity)) & """" & LF &
        "maximum_tasks_per_plan =" & Positive'Image (Item.Maximum_Tasks_Per_Plan) & LF &
        "maximum_findings_per_task =" & Positive'Image (Item.Maximum_Findings_Per_Task) & LF &
        "allow_investigation_tasks = " & Boolean_Image (Item.Allow_Investigation_Tasks) & LF &
        "require_review = " & Boolean_Image (Item.Require_Review) & LF &
        "agent_max_context_bytes =" & Positive'Image (Item.Agent_Max_Context_Bytes) & LF &
        "agent_max_file_bytes =" & Positive'Image (Item.Agent_Max_File_Bytes) & LF &
        "agent_max_response_bytes =" & Positive'Image (Item.Agent_Max_Response_Bytes) & LF &
        "agent_timeout_seconds =" & Positive'Image (Item.Agent_Timeout_Seconds) & LF &
        "[operations]" & LF &
        "maximum_recovery_operations =" & Positive'Image (Item.Maximum_Recovery_Operations) & LF &
        "maximum_history_items =" & Positive'Image (Item.Maximum_History_Items) & LF &
        "maximum_persisted_text_bytes =" &
          Positive'Image (Item.Maximum_Persisted_Text_Bytes) & LF &
        "[workflow]" & LF &
        "task_kind = """ & To_String (Item.Task_Kind) & """" & LF &
        "publication = ""candidate""" & LF &
        "require_initialized_project = " & Boolean_Image (Item.Require_Initialized) & LF &
        "[verification]" & LF &
        "require_fresh_measurement = " & Boolean_Image (Item.Require_Fresh_Measurement) & LF &
        "require_same_policy = " & Boolean_Image (Item.Require_Same_Policy) & LF &
        "require_same_toolchain = " & Boolean_Image (Item.Require_Same_Toolchain) & LF &
        "require_no_new_critical_findings = " & Boolean_Image (Item.Require_No_New_Critical) & LF &
        "[output]" & LF &
        "maximum_output_items =" & Positive'Image (Item.Maximum_Output_Items) & LF &
        "format = """ & (if Item.Format = Terminal_Format then "terminal" else "json") & """" & LF &
        "color = """ &
          (case Item.Color is when Color_Auto => "auto", when Color_Always => "always", when Color_Never => "never") &
          """" & LF;
   end Image;
end Improve.Config;

