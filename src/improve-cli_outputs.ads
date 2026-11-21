with Improve.CLI;
with Improve.Config;
with Improve.Refinement;

--  Command-specific output orchestration behind the CLI process boundary.
private package Improve.CLI_Outputs is
   --  Execute a plan subcommand and serialize its result in the selected format.
   function Plan_Output
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings;
      Provider : access Improve.Refinement.Adapter'Class) return String;

   --  Load task views and serialize them in the selected format.
   function Tasks_Output
     (Item                        : Improve.CLI.Invocation;
      Settings                    : Improve.Config.Settings;
      Quality_Database_Configured : Boolean) return String;

   --  Reconcile task state and serialize the resulting status view.
   function Status_Output
     (Item : Improve.CLI.Invocation; Settings : Improve.Config.Settings) return String;
end Improve.CLI_Outputs;
