with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada_Quality.Types;
with Hostkit.Fs;
with Improve.Dependencies;
with Improve.Findings;

package body Improve.Refinement is
   use Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Hostkit.Fs.Read_Beneath_Outcome;

   LF : constant Character := Character'Val (10);

   function Image (Value : Source_State) return String is
     (case Value is
         when Source_Available => "available",
         when Source_Missing => "missing",
         when Source_Outside => "outside",
         when Source_Too_Large => "too_large",
         when Source_Not_File => "not_file",
         when Source_Read_Failed => "read_failed");

   function Image (Value : Refinement_Status) return String is
     (case Value is
         when Refined => "refined",
         when Unavailable_Fallback => "unavailable_fallback",
         when Timeout_Fallback => "timeout_fallback",
         when Malformed_Fallback => "malformed_fallback",
         when Rejected_Fallback => "rejected_fallback",
         when Adapter_Error_Fallback => "adapter_error_fallback");

   procedure Append_Bounded
     (Target : in out UString;
      Text   : String;
      Limit  : Natural;
      Used   : in out Natural) is
      Room : constant Natural := (if Used >= Limit then 0 else Limit - Used);
      Take : constant Natural := Natural'Min (Room, Text'Length);
   begin
      if Take > 0 then
         Append (Target, Text (Text'First .. Text'First + Take - 1));
         Used := Used + Take;
      end if;
   end Append_Bounded;

   function Source_State_Of (Value : Hostkit.Fs.Read_Beneath_Outcome) return Source_State is
     (case Value is
         when Hostkit.Fs.Read_Done => Source_Available,
         when Hostkit.Fs.Read_Outside => Source_Outside,
         when Hostkit.Fs.Read_Missing => Source_Missing,
         when Hostkit.Fs.Read_Not_File => Source_Not_File,
         when Hostkit.Fs.Read_Too_Large => Source_Too_Large,
         when Hostkit.Fs.Read_Failed | Hostkit.Fs.Read_Unsupported => Source_Read_Failed);

   function Build_Context
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Planning_Context is
      Result : Planning_Context;
      Used   : Natural := 0;
      Files  : Improve.Model.UString_Vectors.Vector;
      Limit  : constant Natural := Settings.Agent_Max_Context_Bytes;
      Schema : constant String :=
        "proposal fields: task_id, category, title, goal_addendum, scope_addendum, acceptance_addendum, " &
        "verification_addendum, relevant_files, dependencies, finding_keys, confidence, " &
        "preserves_quality_policy; task_id/category/finding_keys and deterministic dependencies are mandatory; " &
        "files must exist beneath project_root; acceptance and verification add to, never replace, deterministic " &
        "requirements; no commands or source edits are authorized";

      procedure Add (Target : in out UString; Text : String) is
      begin
         Append_Bounded (Target, Text, Limit, Used);
      end Add;

      procedure Add_Task (Target : in out UString; Value : Improve.Model.Task_Specification) is
      begin
         Add
           (Target,
            "task_id=" & To_String (Value.Id) & LF &
            "category=" & To_String (Value.Category) & LF &
            "title=" & To_String (Value.Title) & LF &
            "goal=" & To_String (Value.Goal) & LF &
            "scope=" & To_String (Value.Scope) & LF &
            "acceptance=" & To_String (Value.Acceptance) & LF &
            "verification=" & To_String (Value.Verification) & LF);
      end Add_Task;
   begin
      Result.Project_Id := Draft.Project.Id;
      Result.Assessment_Run := Draft.Baseline.Run_Id;
      declare
         Fixed_Size : constant Natural :=
           Length (Draft.Project.Name) + Length (Draft.Project.Path) + Length (Draft.Baseline.Policy_Id) +
           Length (Draft.Baseline.Toolchain_Id);
      begin
         if Fixed_Size > Limit then
            raise Data_Error with "agent context limit is smaller than project identity";
         end if;
         Result.Project_Name := Draft.Project.Name;
         Result.Project_Root := Draft.Project.Path;
         Result.Policy := Draft.Baseline.Policy_Id;
         Result.Toolchain := Draft.Baseline.Toolchain_Id;
         Used := Fixed_Size;
      end;
      Add (Result.Required_Schema, Schema);
      for Finding of Draft.Findings loop
         Add
           (Result.Evidence,
            Ada_Quality.Types.Image (Finding.Indicator) & "|" & To_String (Finding.Rule) & "|" &
            To_String (Finding.Fingerprint) & "|" & To_String (Finding.Relative_Path) & "|" &
            To_String (Finding.Message) & "|" & To_String (Finding.Evidence) & LF);
      end loop;
      for Spec of Draft.Tasks loop
         Add_Task (Result.Draft_Tasks, Spec);
         for File of Spec.Relevant_Files loop
            if not Files.Contains (File) then Files.Append (File); end if;
         end loop;
      end loop;
      for Spec of Existing_Tasks loop
         Add_Task (Result.Existing_Tasks, Spec);
      end loop;
      for File of Files loop
         exit when Used >= Limit;
         declare
            Text    : UString;
            Outcome : Hostkit.Fs.Read_Beneath_Outcome;
            Item    : Source_Excerpt;
            Before  : Natural;
         begin
            Hostkit.Fs.Read_Beneath
              (To_String (Draft.Project.Path), To_String (File), Settings.Agent_Max_File_Bytes, Text, Outcome);
            Item.Relative_Path := File;
            Item.State := Source_State_Of (Outcome);
            if Used + Length (File) > Limit then exit; end if;
            Used := Used + Length (File);
            if Outcome = Hostkit.Fs.Read_Done then
               Before := Used;
               Append_Bounded (Item.Content, To_String (Text), Limit, Used);
               Item.Truncated := Used - Before < Length (Text);
            elsif Outcome = Hostkit.Fs.Read_Too_Large then
               Item.Truncated := True;
            end if;
            Result.Sources.Append (Item);
         end;
      end loop;
      Result.Byte_Count := Used;
      return Result;
   end Build_Context;

   function Same
     (Left, Right : Improve.Model.UString_Vectors.Vector) return Boolean is
   begin
      if Left.Length /= Right.Length then return False; end if;
      for Index in 1 .. Natural (Left.Length) loop
         if Left (Index) /= Right (Index) then return False; end if;
      end loop;
      return True;
   end Same;

   function Contains_All
     (Values, Required : Improve.Model.UString_Vectors.Vector) return Boolean is
   begin
      for Value of Required loop
         if not Values.Contains (Value) then return False; end if;
      end loop;
      return True;
   end Contains_All;

   function Has_Duplicates (Values : Improve.Model.UString_Vectors.Vector) return Boolean is
   begin
      for Left in 1 .. Natural (Values.Length) loop
         for Right in Left + 1 .. Natural (Values.Length) loop
            if Values (Left) = Values (Right) then return True; end if;
         end loop;
      end loop;
      return False;
   end Has_Duplicates;

   function Clean (Text : String; Empty_Allowed : Boolean := True) return Boolean is
   begin
      if not Empty_Allowed and then Text = "" then return False; end if;
      for Value of Text loop
         if Character'Pos (Value) < 32 and then Value not in ASCII.HT | ASCII.LF | ASCII.CR then return False; end if;
      end loop;
      return True;
   end Clean;

   function Weakens_Quality (Text : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Text);
      function Has (Pattern : String) return Boolean is (Ada.Strings.Fixed.Index (Lower, Pattern) > 0);
   begin
      return Has ("disable quality") or else Has ("disable the quality") or else Has ("skip verification") or else
        Has ("ignore failure") or else Has ("lower threshold") or else Has ("remove check") or else
        Has ("exclude from quality");
   end Weakens_Quality;

   function Response_Size (Value : Agent_Response) return Natural is
      Result : Natural := Length (Value.Diagnostic);

      procedure Add (Amount : Natural) is
      begin
         if Result > Natural'Last - Amount then Result := Natural'Last;
         else Result := Result + Amount;
         end if;
      end Add;
   begin
      for Proposal of Value.Proposals loop
         Add (Length (Proposal.Task_Id));
         Add (Length (Proposal.Category));
         Add (Length (Proposal.Title));
         Add (Length (Proposal.Goal_Addendum));
         Add (Length (Proposal.Scope_Addendum));
         Add (Length (Proposal.Acceptance_Addendum));
         Add (Length (Proposal.Verification_Addendum));
         for Text of Proposal.Relevant_Files loop Add (Length (Text)); end loop;
         for Text of Proposal.Dependencies loop Add (Length (Text)); end loop;
         for Text of Proposal.Finding_Keys loop Add (Length (Text)); end loop;
      end loop;
      return Result;
   end Response_Size;

   function Task_Index
     (Tasks : Improve.Model.Task_Vectors.Vector;
      Id    : UString) return Natural is
   begin
      for Index in 1 .. Natural (Tasks.Length) loop
         if Tasks (Index).Id = Id then return Index; end if;
      end loop;
      return 0;
   end Task_Index;

   function File_Is_Authorized
     (Root     : String;
      Relative : String;
      Most     : Positive) return Boolean is
      Text    : UString;
      Outcome : Hostkit.Fs.Read_Beneath_Outcome;
   begin
      if not Improve.Findings.Safe_Relative_Path (Relative) or else Relative = "" then return False; end if;
      Hostkit.Fs.Read_Beneath (Root, Relative, Most, Text, Outcome);
      return Outcome in Hostkit.Fs.Read_Done | Hostkit.Fs.Read_Too_Large;
   end File_Is_Authorized;

   procedure Append_Advisory (Target : in out UString; Value : UString) is
   begin
      if Length (Value) > 0 then Append (Target, LF & "Agent refinement (advisory): " & To_String (Value)); end if;
   end Append_Advisory;

   function Validate
     (Draft        : Improve.Model.Plan_Revision;
      Settings     : Improve.Config.Settings;
      Adapter_Name : String;
      Response     : Agent_Response) return Improve.Model.Plan_Revision is
      Result : Improve.Model.Plan_Revision := Draft;
      Seen   : Improve.Model.UString_Vectors.Vector;
   begin
      if Adapter_Name = "" or else Adapter_Name'Length > 80 or else not Clean (Adapter_Name, False) then
         raise Data_Error with "agent adapter identity is invalid";
      elsif Response.Proposals.Is_Empty then
         raise Data_Error with "agent returned no task proposals";
      elsif Response.Proposals.Length > Draft.Tasks.Length or else
        Response.Proposals.Length > Ada.Containers.Count_Type (Settings.Maximum_Tasks_Per_Plan)
      then
         raise Data_Error with "agent proposal count exceeds deterministic plan bounds";
      elsif Response_Size (Response) > Settings.Agent_Max_Response_Bytes then
         raise Data_Error with "agent response exceeds planning.agent_max_response_bytes";
      end if;
      for Proposal of Response.Proposals loop
         declare
            Index : constant Natural := Task_Index (Result.Tasks, Proposal.Task_Id);
         begin
            if Index = 0 then
               raise Data_Error with "agent proposal refers to an unknown Improve task";
            elsif Seen.Contains (Proposal.Task_Id) then
               raise Data_Error with "agent returned more than one proposal for an Improve task";
            end if;
            Seen.Append (Proposal.Task_Id);
            declare Base : constant Improve.Model.Task_Specification := Draft.Tasks (Index); begin
               if Proposal.Category /= Base.Category then
                  raise Data_Error with "agent proposal uses an unsupported task category";
               elsif not Same (Proposal.Finding_Keys, Base.Finding_Keys) then
                  raise Data_Error with "agent proposal invents, removes, or reorders evidence identities";
               elsif not Clean (To_String (Proposal.Title), False) or else Length (Proposal.Title) > 240 then
                  raise Data_Error with "agent proposal title is missing or invalid";
               elsif not Clean (To_String (Proposal.Goal_Addendum)) or else
                 not Clean (To_String (Proposal.Scope_Addendum)) or else
                 not Clean (To_String (Proposal.Acceptance_Addendum)) or else
                 not Clean (To_String (Proposal.Verification_Addendum))
               then
                  raise Data_Error with "agent proposal contains invalid control text";
               elsif not Proposal.Preserves_Quality_Policy or else
                 Weakens_Quality
                   (To_String (Proposal.Title) & LF & To_String (Proposal.Goal_Addendum) & LF &
                    To_String (Proposal.Scope_Addendum) & LF & To_String (Proposal.Acceptance_Addendum) & LF &
                    To_String (Proposal.Verification_Addendum))
               then
                  raise Data_Error with "agent proposal attempts to weaken quality policy";
               elsif Has_Duplicates (Proposal.Relevant_Files) or else Has_Duplicates (Proposal.Dependencies) then
                  raise Data_Error with "agent proposal contains duplicate files or dependencies";
               elsif not Contains_All (Proposal.Relevant_Files, Base.Relevant_Files) then
                  raise Data_Error with "agent proposal removes deterministic file scope";
               elsif not Contains_All (Proposal.Dependencies, Base.Dependencies) then
                  raise Data_Error with "agent proposal removes a deterministic dependency";
               end if;
               for File of Proposal.Relevant_Files loop
                  if not File_Is_Authorized
                    (To_String (Draft.Project.Path), To_String (File), Settings.Agent_Max_File_Bytes)
                  then
                     raise Data_Error with "agent proposal refers to a missing or unauthorized file: " &
                       To_String (File);
                  end if;
               end loop;
               for Dependency of Proposal.Dependencies loop
                  if Task_Index (Result.Tasks, Dependency) = 0 then
                     raise Data_Error with "agent proposal refers to an unknown task dependency";
                  end if;
               end loop;
               Result.Tasks (Index).Title := Proposal.Title;
               Append_Advisory (Result.Tasks (Index).Goal, Proposal.Goal_Addendum);
               Append_Advisory (Result.Tasks (Index).Scope, Proposal.Scope_Addendum);
               Append_Advisory (Result.Tasks (Index).Acceptance, Proposal.Acceptance_Addendum);
               Append_Advisory (Result.Tasks (Index).Verification, Proposal.Verification_Addendum);
               Result.Tasks (Index).Relevant_Files := Proposal.Relevant_Files;
               Result.Tasks (Index).Dependencies := Proposal.Dependencies;
               Result.Tasks (Index).Confidence := Natural'Min (Base.Confidence, Proposal.Confidence);
            end;
         end;
      end loop;
      Improve.Dependencies.Validate (Result.Tasks);
      declare Material : UString := To_Unbounded_String (To_String (Draft.Fingerprint) & "|" & Adapter_Name); begin
         for Spec of Result.Tasks loop
            Append
              (Material,
               "|" & To_String (Spec.Id) & "|" & To_String (Spec.Title) & "|" & To_String (Spec.Goal) & "|" &
               To_String (Spec.Scope) & "|" & To_String (Spec.Acceptance) & "|" &
               To_String (Spec.Verification) & "|" & Natural'Image (Spec.Confidence));
            for File of Spec.Relevant_Files loop Append (Material, "|file:" & To_String (File)); end loop;
            for Dependency of Spec.Dependencies loop
               Append (Material, "|dependency:" & To_String (Dependency));
            end loop;
         end loop;
         Result.Fingerprint := To_Unbounded_String (Stable_Digest (To_String (Material)));
         Result.Plan_Id := To_Unbounded_String ("PLAN-DRAFT-" & To_String (Result.Fingerprint));
         Result.Planner_Id := Result.Planner_Id & To_Unbounded_String ("+agent:" & Adapter_Name);
      end;
      return Result;
   end Validate;

   function Fallback
     (Draft      : Improve.Model.Plan_Revision;
      Status     : Refinement_Status;
      Diagnostic : String) return Refinement_Result is
     ((Plan => Draft, Status => Status, Diagnostic => To_Unbounded_String (Diagnostic)));

   function Refine
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Provider       : not null access Adapter'Class;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Refinement_Result is
      Context       : constant Planning_Context := Build_Context (Draft, Settings, Existing_Tasks);
      Response      : Agent_Response;
      Adapter_Name  : UString;
      Deadline_Hit  : Boolean := False;
   begin
      begin
         select
            delay Duration (Settings.Agent_Timeout_Seconds);
            Deadline_Hit := True;
         then abort
            Adapter_Name := To_Unbounded_String (Name (Provider.all));
            Request (Provider.all, Context, Settings.Agent_Timeout_Seconds, Response);
         end select;
      exception
         when Error : others =>
            return Fallback
              (Draft, Adapter_Error_Fallback, "agent adapter failed: " & Ada.Exceptions.Exception_Message (Error));
      end;
      if Deadline_Hit or else Response.Status = Agent_Timed_Out then
         return Fallback (Draft, Timeout_Fallback, "agent refinement timed out");
      elsif Response.Status = Agent_Unavailable then
         return Fallback (Draft, Unavailable_Fallback, To_String (Response.Diagnostic));
      elsif Response.Status = Malformed_Response then
         return Fallback (Draft, Malformed_Fallback, To_String (Response.Diagnostic));
      end if;
      begin
         return
           (Plan       => Validate (Draft, Settings, To_String (Adapter_Name), Response),
            Status     => Refined,
            Diagnostic => Response.Diagnostic);
      exception
         when Error : Data_Error | Argument_Error =>
            return Fallback (Draft, Rejected_Fallback, Ada.Exceptions.Exception_Message (Error));
      end;
   end Refine;
end Improve.Refinement;
