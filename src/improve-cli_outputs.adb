with Ada.Containers;
with Ada.Strings.Unbounded;
with Improve.CLI_Support;
with Improve.JSON;
with Improve.Model;
with Improve.Operations.Inspection;
with Improve.Operations.Planning;
with Improve.Presentation;
with Improve.Results;
with Improve.State;
with Improve.Tasks;

package body Improve.CLI_Outputs is
   use Ada.Strings.Unbounded;
   use Improve.CLI;
   use Improve.CLI_Support;
   use Improve.Config;
   use type Ada.Containers.Count_Type;
   LF : constant Character := Character'Val (10);

   function Plan_Output
     (Item     : Invocation;
      Settings : Improve.Config.Settings;
      Provider : access Improve.Refinement.Adapter'Class) return String is
   begin
      if Item.Plan_Action = Diff_Plan then
         declare
            Compared : constant Improve.Results.Plan_Comparison :=
              Improve.Operations.Planning.Compare
                (State_Path (Item), To_String (Item.Target), Positive (Item.Against_Revision),
                 Positive (Item.Revision), Improve.Operations.Storage_Limits (Settings));
            function Render return String is (Improve.Presentation.Plan_Comparison (Compared, False));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Comparison (Compared, False); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = Explain_Plan then
         declare
            Compared : constant Improve.Results.Plan_Comparison :=
              Improve.Operations.Planning.Explain
                (State_Path (Item), To_String (Item.Target), Item.Revision,
                 Improve.Operations.Storage_Limits (Settings));
            function Render return String is (Improve.Presentation.Plan_Comparison (Compared, True));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Comparison (Compared, True); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = Approve_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Approve
                (State_Path (Item), To_String (Item.Target), Improve.Operations.Storage_Limits (Settings));
            function Render return String is (Improve.Presentation.Plan_Approval (Plan));
         begin
            if Item.Format = JSON_Format then return Improve.JSON.Plan_Approval (Plan); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action in Show_Plan | Graph_Plan then
         declare
            Plan : constant Improve.Model.Plan_Revision :=
              Improve.Operations.Planning.Load
                (State_Path (Item), To_String (Item.Target),
                 (if Item.Has_Revision then Item.Revision else 0),
                 Improve.Operations.Storage_Limits (Settings));
            function Render return String is
              (if Item.Plan_Action = Graph_Plan then Improve.Presentation.Plan_Graph (Plan)
               else Improve.Presentation.Plan (Plan));
         begin
            Require_Output_Items (Plan.Tasks.Length, Settings.Maximum_Output_Items, "plan task output");
            if Item.Plan_Action = Graph_Plan and then Item.Format = JSON_Format then
               return Improve.JSON.Plan_Graph (Plan);
            elsif Item.Format = JSON_Format then
               return Improve.JSON.Plan (Plan, Dry_Run => False);
            end if;
            return Render_Terminal (Item, Render'Access);
         end;
      elsif Item.Plan_Action = List_Plans then
         declare
            Limit : constant Positive :=
              (if Item.Has_Limit or else Item.Has_Cursor then Page_Limit (Item, Settings)
               else Settings.Maximum_Output_Items);
            Values : Improve.State.Summary_Vectors.Vector :=
              Improve.Operations.Planning.List
                (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
                 Query_Maximum (Item, Settings, Settings.Maximum_History_Items),
                 Improve.Operations.Storage_Limits (Settings),
                 Improve.Operations.Quality_Load_Limits (Settings), Improve.Config.Evidence_Limits_Of (Settings));
            Next : Unbounded_String;
            function Render return String is
              (Improve.Presentation.Plans (Values) &
               (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
         begin
            if Item.Has_Limit or else Item.Has_Cursor then
               if Item.Cursor >= Natural (Values.Length) then Values.Clear;
               elsif Item.Cursor > 0 then Values.Delete_First (Ada.Containers.Count_Type (Item.Cursor)); end if;
               if Natural (Values.Length) > Limit then
                  Next := To_Unbounded_String (Number (Item.Cursor + Limit));
                  Values.Delete_Last (Values.Length - Ada.Containers.Count_Type (Limit));
               end if;
            end if;
            if Item.Format = JSON_Format then return Improve.JSON.Plans (Values, To_String (Next)); end if;
            return Render_Terminal (Item, Render'Access);
         end;
      end if;
      if Settings.Agent_Enabled and then Provider = null then
         raise Dependency_Error with "planning.agent_enabled requires the improve-model-runner executable";
      end if;
      if Settings.Agent_Enabled then
         declare
            Identity : constant Improve.Refinement.Adapter_Provenance := Improve.Refinement.Provenance (Provider.all);
            Digest   : constant String := To_String (Identity.Model_SHA256);
            Expected : constant String := To_String (Settings.Agent_Model_SHA256);
         begin
            if Expected /= "" then
               if Digest'Length /= 64 or else Digest = [1 .. 64 => '0'] or else
                 (for some C of Digest => C not in '0' .. '9' | 'a' .. 'f')
               then
                  raise Dependency_Error with "configured model runtime did not open successfully";
               elsif Digest /= Expected then
                  raise Dependency_Error with "configured model SHA-256 does not match the opened model";
               end if;
            end if;
         end;
      end if;
      declare
         Executed : constant Improve.Operations.Planning.Generation_Result :=
           Improve.Operations.Planning.Generate
             (State_Path (Item), Quality_Path (Item, Settings), To_String (Item.Project),
              Item.Run_Id, Settings, Item.Dry_Run, Provider => (if Settings.Agent_Enabled then Provider else null));
         Plan : constant Improve.Model.Plan_Revision := Executed.Plan;
         function Render return String is
           (Improve.Presentation.Generated_Plan (Plan, Item.Dry_Run, Executed.Existing));
      begin
         if Item.Format = JSON_Format then return Improve.JSON.Plan (Plan, Item.Dry_Run); end if;
         return Render_Terminal (Item, Render'Access);
      end;
   end Plan_Output;
   function Tasks_Output
     (Item                        : Invocation;
      Settings                    : Improve.Config.Settings;
      Quality_Database_Configured : Boolean) return String is
      Filter   : constant String := (if Item.Has_Status then To_String (Item.Status_Filter) else "all");
      Limit    : constant Positive :=
        (if Item.Has_Limit or else Item.Has_Cursor then Page_Limit (Item, Settings)
         else Settings.Maximum_Output_Items);
      Filtered : Improve.Tasks.View_Vectors.Vector :=
        Improve.Operations.Inspection.Tasks
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.Has_Project then To_String (Item.Project) else ""),
           Task_Id          => (if Item.Has_Task then To_String (Item.Task_Id) else ""),
           Revision         => Item.Revision,
           Filter           => Filter,
           Maximum_Items    => Query_Maximum (Item, Settings, Settings.Maximum_History_Items),
           Require_Quality  => Item.Has_Database or else Quality_Database_Configured,
           Limits           => Improve.Operations.Storage_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
          Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));

      Next : Unbounded_String;
      function Render return String is
        (Improve.Presentation.Tasks (Filtered) &
         (if Length (Next) = 0 then "" else "Next cursor: " & To_String (Next) & LF));
   begin
      if Item.Has_Limit or else Item.Has_Cursor then
         if Item.Cursor >= Natural (Filtered.Length) then
            Filtered.Clear;
         elsif Item.Cursor > 0 then
            Filtered.Delete_First (Ada.Containers.Count_Type (Item.Cursor));
         end if;
         if Natural (Filtered.Length) > Limit then
            Next := To_Unbounded_String (Number (Item.Cursor + Limit));
            Filtered.Delete_Last (Filtered.Length - Ada.Containers.Count_Type (Limit));
         end if;
      end if;
      if Item.Format = JSON_Format then
         return Improve.JSON.Tasks (Filtered, Filter, To_String (Next));
      end if;
      return Render_Terminal (Item, Render'Access);
   end Tasks_Output;
   function Status_Output (Item : Invocation; Settings : Improve.Config.Settings) return String is
      Values : constant Improve.Tasks.Status_Vectors.Vector :=
        Improve.Operations.Inspection.Status
          (State_Path       => State_Path (Item),
           Quality_Path     => Quality_Path (Item, Settings),
           Project_Selector => (if Item.All_Projects then "" else To_String (Item.Project)),
           All_Projects     => Item.All_Projects,
           Maximum_Items    => Settings.Maximum_Output_Items,
           Limits           => Improve.Operations.Storage_Limits (Settings),
           Quality_Limits   => Improve.Operations.Quality_Load_Limits (Settings),
           Evidence_Limits  => Improve.Config.Evidence_Limits_Of (Settings));

      function Render return String is
        (Improve.Presentation.Status (Values));
   begin
      if Item.Format = JSON_Format then
         return Improve.JSON.Status (Values);
      end if;
      return Render_Terminal (Item, Render'Access);
   end Status_Output;

end Improve.CLI_Outputs;
