separate (Improve.Config)
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
            when Agent_Enabled =>
               Result.Agent_Enabled := Boolean_Setting (Id);
            when Agent_Model =>
               Result.Agent_Model := To_Unbounded_String (String_Setting (Id));
            when Agent_Model_Path =>
               Result.Agent_Model_Path := To_Unbounded_String (String_Setting (Id));
            when Agent_Model_SHA256 =>
               Result.Agent_Model_SHA256 := To_Unbounded_String (String_Setting (Id));
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
         Present (Maximum_Migration_Rows) or else Present (Maximum_Persisted_Total_Bytes) or else
         Present (Agent_Enabled) or else Present (Agent_Model) or else Present (Agent_Model_Path) or else
         Present (Agent_Model_SHA256))
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
      Validate (Result);
      return
        (Values => Result, Source_Path => To_Unbounded_String (Path),
         Quality_Database_Configured => Present (Quality_Database));
   end;
end Load_With_Provenance;

