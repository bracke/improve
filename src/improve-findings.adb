with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded;

package body Improve.Findings is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Improve.Model.Candidate_Kind;

   package Seen_Maps is new Ada.Containers.Indefinite_Ordered_Maps
     (Key_Type => String, Element_Type => Boolean);

   function Safe_Relative_Path (Path : String) return Boolean is
      Start : Positive := Path'First;
   begin
      if Path = "" then return True; end if;
      if Path (Path'First) in '/' | '\' or else
        (Path'Length >= 2 and then Path (Path'First + 1) = ':')
      then
         return False;
      end if;
      for Index in Path'Range loop
         if Path (Index) in '/' | '\' then
            if Index = Start or else Path (Start .. Index - 1) = ".." then return False; end if;
            Start := Index + 1;
         end if;
      end loop;
      return Start <= Path'Last and then Path (Start .. Path'Last) /= "..";
   end Safe_Relative_Path;

   function Normalize
     (Selected         : Improve.Source.Selection;
      Minimum_Severity : Severity := Low;
      Allow_Investigation : Boolean := True) return Improve.Model.Finding_Vectors.Vector is
      Result : Improve.Model.Finding_Vectors.Vector;
      Seen   : Seen_Maps.Map;

      procedure Add (Item : Improve.Model.Finding_Reference) is
         Key : constant String :=
           Positive'Image (Item.Project_Id) & "|" & Image (Item.Indicator) & "|" & To_String (Item.Rule) & "|" &
           To_String (Item.Fingerprint) & "|" & To_String (Item.Semantic_Subject);
      begin
         if not Seen.Contains (Key) then
            Seen.Insert (Key, True);
            Result.Append (Item);
         end if;
      end Add;

      procedure Add_Indicator (Value : Indicator_Result; Kind : Improve.Model.Candidate_Kind; Prefix : String) is
         Subject : constant String := Image (Value.Indicator);
         Summary : constant String := To_String (Value.Summary);
      begin
         Add
           ((Project_Id       => Selected.Project.Id,
             Run_Id           => Selected.Assessment.Run.Id,
             Indicator        => Value.Indicator,
             Rule             => To_Unbounded_String (Prefix),
             Level            => (if Kind = Improve.Model.Remediation_Candidate then Medium else Low),
             Relative_Path    => Null_Unbounded_String,
             Line             => 0,
             Fingerprint      => To_Unbounded_String
               (Prefix & ":" & Image (Value.Indicator) & ":" & Stable_Digest (Summary & To_String (Value.Evidence))),
             Semantic_Subject => To_Unbounded_String (Subject),
             Message          => Value.Summary,
             Evidence         => Value.Evidence,
             Kind             => Kind,
             Indicator_Level  => True));
      end Add_Indicator;
   begin
      for Value of Selected.Assessment.Results loop
         if not Is_Valid (Value) then
            raise Data_Error with "invalid indicator state for " & Image (Value.Indicator);
         end if;
         case Value.Execution is
            when Succeeded =>
               if Value.Compliance = Violation then
                  if Value.Findings.Is_Empty then
                     Add_Indicator (Value, Improve.Model.Remediation_Candidate, "indicator-violation");
                  else
                     for Finding of Value.Findings loop
                        if Finding.Indicator /= Value.Indicator then
                           raise Data_Error with "finding indicator does not match its owning result";
                        elsif Length (Finding.Fingerprint) = 0 then
                           raise Data_Error with "finding has no stable fingerprint for " & Image (Value.Indicator);
                        elsif not Safe_Relative_Path (To_String (Finding.Relative_Path)) then
                           raise Data_Error with "unsafe finding path: " & To_String (Finding.Relative_Path);
                        elsif Finding.Level >= Minimum_Severity then
                           declare
                              Subject : constant Ada.Strings.Unbounded.Unbounded_String :=
                                (if Length (Finding.Relative_Path) > 0 then Finding.Relative_Path
                                 elsif Length (Finding.Rule) > 0 then Finding.Rule
                                 else To_Unbounded_String (Image (Finding.Indicator)));
                           begin
                              Add
                                ((Project_Id       => Selected.Project.Id,
                                  Run_Id           => Selected.Assessment.Run.Id,
                                  Indicator        => Finding.Indicator,
                                  Rule             => Finding.Rule,
                                  Level            => Finding.Level,
                                  Relative_Path    => Finding.Relative_Path,
                                  Line             => Finding.Line,
                                  Fingerprint      => Finding.Fingerprint,
                                  Semantic_Subject => Subject,
                                  Message          => Finding.Message,
                                  Evidence         => Value.Evidence,
                                  Kind             => Improve.Model.Remediation_Candidate,
                                  Indicator_Level  => False));
                           end;
                        end if;
                     end loop;
                  end if;
               end if;
            when Not_Applicable => null;
            when Not_Run | Running | Blocked | Failed | Errored =>
               if Allow_Investigation then
                  Add_Indicator
                    (Value,
                     (if Value.Execution in Blocked | Failed then Improve.Model.Diagnostic_Candidate
                      else Improve.Model.Investigation_Candidate),
                     "unavailable-evidence");
               end if;
         end case;
      end loop;
      return Result;
   end Normalize;
end Improve.Findings;
