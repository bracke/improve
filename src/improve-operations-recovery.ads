with Ada_Quality.Reporting;
with Improve.Config;
with Improve.Results;
with Improve.Storage;

--  Interrupted native-publication recovery use case.
package Improve.Operations.Recovery is
   --  Keep recovery orchestration behind the application-operation boundary.

   subtype Result is Improve.Results.Recovery_Result;
   --  Work recovered by one bounded invocation.

   function Run
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits) return Result;
   --  Recover bounded, explicitly authorized publication operations.
   --  @param State_Path Existing Improve state database.
   --  @param Quality_Path Existing read-only Ada Quality database.
   --  @param Requested_Kind Configured harness task kind or auto.
   --  @param Maximum Maximum journal operations to recover.
   --  @param Limits Hard persistence and history limits.
   --  @param Quality_Limits Hard quality snapshot row limits.
   --  @param Evidence_Limits Shared quality evidence and source identity limits.
   --  @return Recovery counts.
end Improve.Operations.Recovery;
