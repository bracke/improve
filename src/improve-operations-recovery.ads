with Ada_Quality.Reporting;
with Improve.Config;
with Improve.Storage;

--  Interrupted native-publication recovery use case.
package Improve.Operations.Recovery is
   --  Keep recovery orchestration behind the application-operation boundary.

   type Result is record
      Operations_Recovered : Natural := 0;
      Tasks_Recovered      : Natural := 0;
   end record;
   --  Work recovered by one bounded invocation.
   --  @field Operations_Recovered Completed journal operations.
   --  @field Tasks_Recovered Adopted or recovered task mappings.

   function Run
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
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
