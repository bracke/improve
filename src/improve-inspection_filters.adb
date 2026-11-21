with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Improve.Config;
with Improve.Model;

package body Improve.Inspection_Filters is
   use Ada.Strings.Unbounded;
   use type Ada_Quality.Types.Severity;

   function Findings
     (Value     : Improve.Results.Finding_List;
      Indicator : String := "";
      Severity  : String := "";
      Path      : String := "") return Improve.Results.Finding_List is
      Result : Improve.Results.Finding_List := Value;
      Severity_Key : constant String := Ada.Characters.Handling.To_Lower (Severity);
      Parsed_Severity : Improve.Config.Severity_Level;
   begin
      if Severity_Key /= "" and then not Improve.Config.Parse_Severity_Level (Severity_Key, Parsed_Severity) then
         raise Argument_Error with "invalid --severity value " & Severity;
      end if;
      for Index in reverse 1 .. Natural (Result.Values.Length) loop
         declare
            Finding : constant Improve.Model.Finding_Reference := Result.Values (Index);
            Indicator_Matches : constant Boolean :=
              Indicator = "" or else
              Ada.Characters.Handling.To_Lower (Ada_Quality.Types.Image (Finding.Indicator)) =
                Ada.Characters.Handling.To_Lower (Indicator);
            Severity_Matches : constant Boolean :=
              Severity = "" or else
              Improve.Config.Quality_Severity (Parsed_Severity) = Finding.Level;
            Path_Matches : constant Boolean :=
              Path = "" or else Ada.Strings.Fixed.Index (To_String (Finding.Relative_Path), Path) > 0;
         begin
            if not (Indicator_Matches and Severity_Matches and Path_Matches) then
               Result.Values.Delete (Index);
            end if;
         end;
      end loop;
      return Result;
   end Findings;
end Improve.Inspection_Filters;
