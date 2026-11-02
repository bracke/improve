with Ada.Characters.Handling;
with Project_Tools.Files;
with Project_Tools.TOML;

package body Improve.Config is
   use Ada.Strings.Unbounded;
   use type Project_Tools.TOML.Boolean_Parse_Status;
   use type Project_Tools.TOML.Natural_Parse_Status;
   use type Project_Tools.TOML.String_Parse_Status;

   LF : constant Character := Character'Val (10);

   function Defaults return Settings is
     ((Quality_Database          => To_Unbounded_String (".ada-quality.db"),
       Selection                 => Latest_Completed,
       Minimum_Severity          => Low,
       Maximum_Tasks_Per_Plan    => 100,
       Maximum_Findings_Per_Task => 50,
       Allow_Investigation_Tasks => True,
       Require_Review            => True,
       Task_Kind                 => To_Unbounded_String ("auto"),
       Publication               => Candidate_Publication,
       Require_Initialized       => True,
       Require_Fresh_Measurement => True,
       Require_Same_Policy       => True,
       Require_Same_Toolchain    => False,
       Require_No_New_Critical   => True,
       Format                    => Terminal_Format,
       Color                     => Color_Auto));

   function Load (Path : String) return Settings is
      Result : Settings := Defaults;
   begin
      if Path = "" then
         return Result;
      elsif not Project_Tools.Files.File_Exists (Path) then
         raise Argument_Error with "configuration file not found: " & Path;
      end if;
      declare
         Text : constant String := Project_Tools.Files.Read_Raw_File (Path);

         function String_Value (Key : String; Default : String) return String is
            Parsed : constant Project_Tools.TOML.String_Parse_Result :=
              Project_Tools.TOML.Parse_String_After (Text, Key, Text'First);
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_String then
               raise Argument_Error with "malformed string setting: " & Key;
            elsif Parsed.Status = Project_Tools.TOML.Missing_String then
               return Default;
            end if;
            return To_String (Parsed.Value);
         end String_Value;

         function Natural_Value (Key : String; Default : Positive) return Positive is
            Parsed : constant Project_Tools.TOML.Natural_Parse_Result :=
              Project_Tools.TOML.Parse_Natural_After (Text, Key, Text'First);
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

         function Boolean_Value (Key : String; Default : Boolean) return Boolean is
            Parsed : constant Project_Tools.TOML.Boolean_Parse_Result :=
              Project_Tools.TOML.Parse_Boolean_After (Text, Key, Text'First);
         begin
            if Parsed.Status = Project_Tools.TOML.Malformed_Boolean then
               raise Argument_Error with "malformed boolean setting: " & Key;
            elsif Parsed.Status = Project_Tools.TOML.Missing_Boolean then
               return Default;
            end if;
            return Parsed.Value;
         end Boolean_Value;

         Schema : constant Project_Tools.TOML.Natural_Parse_Result :=
           Project_Tools.TOML.Parse_Natural_After (Text, "schema_version", Text'First);
         Selection : constant String := String_Value ("selection", "latest_completed");
         Severity  : constant String := String_Value ("minimum_severity", "low");
         Kind      : constant String := String_Value ("task_kind", "auto");
         Publish   : constant String := String_Value ("publication", "candidate");
         Format    : constant String := String_Value ("format", "terminal");
         Color     : constant String := String_Value ("color", "auto");
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
         Result.Quality_Database := To_Unbounded_String (String_Value ("database", ".ada-quality.db"));
         if Length (Result.Quality_Database) = 0 then
            raise Argument_Error with "quality.database must not be empty";
         end if;
         if Severity = "info" then Result.Minimum_Severity := Info;
         elsif Severity = "low" then Result.Minimum_Severity := Low;
         elsif Severity = "medium" then Result.Minimum_Severity := Medium;
         elsif Severity = "high" then Result.Minimum_Severity := High;
         elsif Severity = "critical" then Result.Minimum_Severity := Critical;
         else raise Argument_Error with "planning.minimum_severity is invalid";
         end if;
         Result.Maximum_Tasks_Per_Plan := Natural_Value ("maximum_tasks_per_plan", 100);
         Result.Maximum_Findings_Per_Task := Natural_Value ("maximum_findings_per_task", 50);
         if Result.Maximum_Tasks_Per_Plan > 10_000 then
            raise Argument_Error with "planning.maximum_tasks_per_plan exceeds 10000";
         elsif Result.Maximum_Findings_Per_Task > 10_000 then
            raise Argument_Error with "planning.maximum_findings_per_task exceeds 10000";
         end if;
         Result.Allow_Investigation_Tasks := Boolean_Value ("allow_investigation_tasks", True);
         Result.Require_Review := Boolean_Value ("require_review", True);
         Result.Task_Kind := To_Unbounded_String (Kind);
         Result.Require_Initialized := Boolean_Value ("require_initialized_project", True);
         Result.Require_Fresh_Measurement := Boolean_Value ("require_fresh_measurement", True);
         Result.Require_Same_Policy := Boolean_Value ("require_same_policy", True);
         Result.Require_Same_Toolchain := Boolean_Value ("require_same_toolchain", False);
         Result.Require_No_New_Critical := Boolean_Value ("require_no_new_critical_findings", True);
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
      return Result;
   end Load;

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Image (Item : Settings) return String is
      function Lower (Text : String) return String is (Ada.Characters.Handling.To_Lower (Text));
   begin
      return
        "schema_version = 1" & LF &
        "quality.database = """ & To_String (Item.Quality_Database) & """" & LF &
        "quality.selection = ""latest_completed""" & LF &
        "planning.minimum_severity = """ & Lower (Severity_Level'Image (Item.Minimum_Severity)) & """" & LF &
        "planning.maximum_tasks_per_plan =" & Positive'Image (Item.Maximum_Tasks_Per_Plan) & LF &
        "planning.maximum_findings_per_task =" & Positive'Image (Item.Maximum_Findings_Per_Task) & LF &
        "planning.allow_investigation_tasks = " & Boolean_Image (Item.Allow_Investigation_Tasks) & LF &
        "planning.require_review = " & Boolean_Image (Item.Require_Review) & LF &
        "workflow.task_kind = """ & To_String (Item.Task_Kind) & """" & LF &
        "workflow.publication = ""candidate""" & LF &
        "workflow.require_initialized_project = " & Boolean_Image (Item.Require_Initialized) & LF &
        "verification.require_fresh_measurement = " & Boolean_Image (Item.Require_Fresh_Measurement) & LF &
        "verification.require_same_policy = " & Boolean_Image (Item.Require_Same_Policy) & LF &
        "verification.require_same_toolchain = " & Boolean_Image (Item.Require_Same_Toolchain) & LF &
        "verification.require_no_new_critical_findings = " & Boolean_Image (Item.Require_No_New_Critical) & LF &
        "output.format = """ & (if Item.Format = Terminal_Format then "terminal" else "json") & """" & LF &
        "output.color = """ &
          (case Item.Color is when Color_Auto => "auto", when Color_Always => "always", when Color_Never => "never") &
          """" & LF;
   end Image;
end Improve.Config;

