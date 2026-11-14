with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Improve.Text;

package body Improve.Presentation is
   use Ada.Strings.Unbounded;
   use Improve.Text;
   use type Improve.Model.Quality_Outcome;
   use type Improve.Tasks.Operational_Status;

   LF : constant Character := Character'Val (10);

   protected Styling_Lock is
      entry Acquire;
      procedure Release;
   private
      Busy : Boolean := False;
   end Styling_Lock;

   protected body Styling_Lock is
      entry Acquire when not Busy is
      begin
         Busy := True;
      end Acquire;

      procedure Release is
      begin
         Busy := False;
      end Release;
   end Styling_Lock;

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Configure
     (Format : Improve.Config.Output_Format;
      Color  : Improve.Config.Color_Mode) return Styling_Scope is
      use Improve.Config;
   begin
      return Result : Styling_Scope do
         Styling_Lock.Acquire;
         Result.Acquired := True;
         Result.Previous := Terminal_Styles.Current_Color_Policy;
         if Format = JSON_Format then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         else
            Terminal_Styles.Set_Color_Policy
              (case Color is
                  when Color_Auto => Terminal_Styles.Color_Auto,
                  when Color_Always => Terminal_Styles.Color_Always,
                  when Color_Never => Terminal_Styles.Color_Never);
         end if;
      end return;
   end Configure;

   overriding procedure Finalize (Item : in out Styling_Scope) is
   begin
      if Item.Acquired then
         begin
            Terminal_Styles.Set_Color_Policy (Item.Previous);
         exception
            when others => null;
         end;
         Styling_Lock.Release;
         Item.Acquired := False;
      end if;
   end Finalize;

   function Header (Text : String) return String is
     (Terminal_Styles.Decorate (Safe_Text (Text), Terminal_Styles.Role_Header));

   function Safe_Text (Text : String) return String is
      function Unsafe (Value : Wide_Wide_Character) return Boolean is
         Position : constant Natural := Wide_Wide_Character'Pos (Value);
      begin
         return Position < 32 or else Position in 127 .. 159 or else
           Position in 16#061C# | 16#200E# | 16#200F# | 16#202A# .. 16#202E# |
             16#2066# .. 16#2069# | 16#FEFF#;
      end Unsafe;
   begin
      declare
         Result : Wide_Wide_String := Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text);
      begin
         for Value of Result loop
            if Unsafe (Value) then Value := ' '; end if;
         end loop;
         return Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Result);
      end;
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         declare Result : String := Text; begin
            for Value of Result loop
               if Character'Pos (Value) < 32 or else Character'Pos (Value) in 127 .. 159 then
                  Value := ' ';
               end if;
            end loop;
            return Result;
         end;
   end Safe_Text;

   procedure Append_Plan_Tasks
     (Result : in out Unbounded_String;
      Value  : Improve.Model.Plan_Revision) is
   begin
      if Value.Tasks.Is_Empty then
         Append (Result, Message ("plan.none") & LF);
      else
         for Spec of Value.Tasks loop
            Append
              (Result,
               To_String (Spec.Id) & "  [" & Improve.Model.Image (Spec.Task_Priority) & "] " &
               Safe_Text (To_String (Spec.Title)) & LF & "  " &
               Safe_Text (To_String (Spec.Acceptance)) & LF);
         end loop;
      end if;
   end Append_Plan_Tasks;

   function Projects (Values : Ada_Quality.Reporting.Project_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Header (Message ("projects.title")) & LF);
      if Values.Is_Empty then
         Append (Result, Message ("projects.none") & LF);
      else
         Append
           (Result, Message ("label.id") & "  " & Message ("label.enabled") & "  " &
            Message ("label.path") & LF);
         for Value of Values loop
            Append
              (Result, Number (Value.Id) & "   " & (if Value.Enabled then "yes" else "no ") & "      " &
               Safe_Text (To_String (Value.Path)) & LF);
         end loop;
      end if;
      return To_String (Result);
   end Projects;

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append
        (Result,
         Header
           (Message
              ("findings.title",
               [Arg ("project", To_String (Selected.Project.Name)),
                Arg ("run", Number (Selected.Assessment.Run.Id))])) & LF);
      if Values.Is_Empty then
         Append (Result, Message ("findings.none") & LF);
      else
         Append
           (Result, Message ("label.indicator") & "  " & Message ("label.severity") & "  " &
            Message ("label.location") & "  " & Message ("label.message") & LF);
         for Value of Values loop
            declare
               Location : constant String :=
                 (if Length (Value.Relative_Path) = 0 then "-"
                  elsif Value.Line = 0 then To_String (Value.Relative_Path)
                  else To_String (Value.Relative_Path) & ":" & Number (Value.Line));
            begin
               Append
                 (Result, Ada_Quality.Types.Image (Value.Indicator) & "  " &
                  Ada_Quality.Types.Severity'Image (Value.Level) & "  " & Safe_Text (Location) & "  " &
                  Safe_Text (To_String (Value.Message)) & LF);
            end;
         end loop;
      end if;
      return To_String (Result);
   end Findings;

   function Plan (Value : Improve.Model.Plan_Revision) return String is
      Result : Unbounded_String;
   begin
      Append
        (Result,
         Header
           (Message
              ("plan.title",
               [Arg ("project", To_String (Value.Project.Name)),
                Arg ("run", Number (Value.Baseline.Run_Id))])) & LF);
      Append (Result, Message ("plan.persisted.identity", [Arg ("id", To_String (Value.Plan_Id))]) & LF);
      Append (Result, Message ("plan.revision", [Arg ("revision", Number (Value.Revision))]) & LF);
      Append_Plan_Tasks (Result, Value);
      return To_String (Result);
   end Plan;

   function Plans (Values : Improve.Storage.Summary_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Header (Message ("plan.list.title")) & LF);
      if Values.Is_Empty then Append (Result, Message ("plan.list.none") & LF); end if;
      for Value of Values loop
         Append
           (Result,
            Message
              ("plan.list.item",
               [Arg ("id", To_String (Value.Plan_Id)), Arg ("revision", Number (Value.Revision)),
                Arg ("tasks", Number (Value.Task_Count)), Arg ("run", Number (Value.Run_Id))]) & LF);
      end loop;
      return To_String (Result);
   end Plans;

   function Generated_Plan
     (Value    : Improve.Model.Plan_Revision;
      Dry_Run  : Boolean;
      Existing : Boolean) return String is
      Result : Unbounded_String;
   begin
      Append
        (Result,
         Header
           (Message
              ("plan.title",
               [Arg ("project", To_String (Value.Project.Name)),
                Arg ("run", Number (Value.Baseline.Run_Id))])) & LF);
      Append
        (Result,
         Message
           ((if Dry_Run then "plan.dry_run" elsif Existing then "plan.existing" else "plan.stored")) & LF);
      Append
        (Result,
         Message
           ((if Dry_Run then "plan.identity" else "plan.persisted.identity"),
            [Arg ("id", To_String (Value.Plan_Id))]) & LF);
      Append_Plan_Tasks (Result, Value);
      return To_String (Result);
   end Generated_Plan;

   function Plan_Approval (Value : Improve.Model.Plan_Revision) return String is
     (Message
        ("plan.approved",
         [Arg ("id", To_String (Value.Plan_Id)), Arg ("revision", Number (Value.Revision))]) & LF);

   function Publication
     (Plan_Id : String;
      Value   : Improve.Workflow.Publication_Result;
      Dry_Run : Boolean) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Header (Message ("apply.title", [Arg ("plan", Plan_Id)])) & LF);
      Append (Result, Message (if Dry_Run then "apply.preview" else "apply.complete") & LF);
      for Item of Value.Tasks loop
         Append
           (Result, To_String (Item.Improve_Id) & " -> " &
            (if Length (Item.Harness_Id) = 0 then "candidate" else To_String (Item.Harness_Id)) & "  " &
            To_String (Item.State) & (if Item.Recovered then " (recovered)" else "") & LF);
      end loop;
      return To_String (Result);
   end Publication;

   function Tasks (Values : Improve.Tasks.View_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      Append (Result, Header (Message ("tasks.title")) & LF);
      if Values.Is_Empty then
         Append (Result, Message ("tasks.none") & LF);
      else
         Append
           (Result, Message ("label.id") & "  " & Message ("label.harness") & "  " &
            Message ("label.status") & "  " & Message ("label.title") & LF);
         for Value of Values loop
            Append
              (Result, To_String (Value.Improve_Id) & "  " &
               (if Length (Value.Harness_Id) = 0 then "-" else To_String (Value.Harness_Id)) & "  " &
               Improve.Tasks.Image (Improve.Tasks.Status (Value)) & "  " &
               Safe_Text (To_String (Value.Title)) & LF);
         end loop;
      end if;
      return To_String (Result);
   end Tasks;

   function Status (Values : Improve.Tasks.Status_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         if Length (Result) > 0 then Append (Result, LF); end if;
         Append
           (Result,
            Header (Message ("status.title", [Arg ("project", Safe_Text (To_String (Value.Project)))])) & LF &
            Message ("status.baseline", [Arg ("run", Number (Value.Baseline_Run))]) & LF &
            Message ("status.latest", [Arg ("run", Number (Value.Latest_Run))]) & LF &
            Message ("status.plans", [Arg ("count", Number (Value.Plan_Count))]) & LF &
            Message ("status.tasks", [Arg ("count", Number (Natural (Value.Tasks.Length)))]) & LF &
            Message
              ("status.plan_quality",
               [Arg
                  ("outcome",
                   (if Value.Has_Plan_Verification and then Value.Plan_Verification_Run = Value.Latest_Run
                    then Improve.Model.Image (Value.Plan_Quality)
                    else Improve.Model.Image (Improve.Model.Unverified)))]) & LF &
            Message
              ("status.project_quality",
               [Arg
                  ("outcome",
                   (if Value.Has_Project_Verification and then Value.Project_Verification_Run = Value.Latest_Run
                    then Improve.Model.Image (Value.Project_Quality)
                    else Improve.Model.Image (Improve.Model.Unverified)))]) & LF);
         if Value.Has_Plan_Verification then
            Append
              (Result,
               Message
                 ("status.last_plan_verification", [Arg ("run", Number (Value.Plan_Verification_Run))]) & LF);
            if Value.Plan_Verification_Run /= Value.Latest_Run then
               Append
                 (Result,
                  Message
                    ("status.previous_plan_result",
                     [Arg ("outcome", Improve.Model.Image (Value.Plan_Quality))]) & LF);
            end if;
         end if;
         if Value.Has_Project_Verification then
            Append
              (Result,
               Message
                 ("status.last_project_verification", [Arg ("run", Number (Value.Project_Verification_Run))]) & LF);
            if Value.Project_Verification_Run /= Value.Latest_Run then
               Append
                 (Result,
                  Message
                    ("status.previous_project_result",
                     [Arg ("outcome", Improve.Model.Image (Value.Project_Quality))]) & LF);
            end if;
         end if;
         for Item in Improve.Tasks.Operational_Status loop
            declare Count : Natural := 0; begin
               for View of Value.Tasks loop
                  if Improve.Tasks.Status (View) = Item then Count := Count + 1; end if;
               end loop;
               if Count > 0 then
                  Append
                    (Result,
                     Message
                       ("status.count",
                        [Arg ("status", Improve.Tasks.Image (Item)), Arg ("count", Number (Count))]) & LF);
               end if;
            end;
         end loop;
         Append
           (Result, Message ("status.findings") & LF &
            Message ("status.count", [Arg ("status", "resolved"),
              Arg ("count", Number (Value.Findings.Resolved))]) & LF &
            Message ("status.count", [Arg ("status", "outstanding"),
              Arg ("count", Number (Value.Findings.Outstanding))]) & LF &
            Message ("status.count", [Arg ("status", "not_measurable"),
              Arg ("count", Number (Value.Findings.Not_Measurable))]) & LF &
            Message ("status.count", [Arg ("status", "regressed"),
              Arg ("count", Number (Value.Findings.Regressed))]) & LF &
            Message ("status.count", [Arg ("status", "superseded"),
              Arg ("count", Number (Value.Findings.Superseded))]) & LF &
            Message ("status.count", [Arg ("status", "previously_resolved"),
              Arg ("count", Number (Value.Findings.Previously_Resolved))]) & LF &
            Message ("status.count", [Arg ("status", "unverified"),
              Arg ("count", Number (Value.Findings.Unverified))]) & LF);
      end loop;
      return To_String (Result);
   end Status;

   function Recovery (Value : Improve.Operations.Recovery.Result) return String is
     (Header (Message ("recover.title")) & LF &
      Message
        ("recover.complete",
         [Arg ("operations", Number (Value.Operations_Recovered)),
          Arg ("tasks", Number (Value.Tasks_Recovered))]) & LF);

   function Verification
     (Plan_Id : String;
      Value   : Improve.Verification.Report;
      Command : String) return String is
      Result : Unbounded_String;
   begin
      Append
        (Result,
         Header
           (Message
              ((if Command = "refresh" then "refresh.title" else "verify.title"),
               [Arg ("plan", Plan_Id)])) & LF);
      Append
        (Result, Message ("verify.outcome", [Arg ("outcome", Improve.Model.Image (Value.Outcome))]) & LF);
      for Item of Value.Tasks loop
         Append (Result, To_String (Item.Task_Id) & "  " & Improve.Model.Image (Item.Outcome) & LF);
      end loop;
      return To_String (Result);
   end Verification;
end Improve.Presentation;

