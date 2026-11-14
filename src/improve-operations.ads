with Improve.Config;
with Improve.Model;
with Improve.Planner;
with Improve.Refinement;
with Improve.Storage;
with Improve.Verification;
with Ada_Quality.Reporting;

--  Application use cases shared by the CLI and other adapters.
package Improve.Operations is
   --  Shared application invariants for operation-specific child packages.

   procedure Require_Project_Identity
     (Expected, Actual : Improve.Model.Project_Reference);
   --  Reject a project resolved from a different quality database or root.
   --  @param Expected Database-qualified identity stored with remediation state.
   --  @param Actual Identity resolved from the selected Ada Quality database.

   function Publication_Namespace (State_Path : String) return String;
   --  Return the canonical namespace used to authenticate native task ownership.
   --  @param State_Path Improve-owned state database path.
   --  @return Stable canonical state-store identity.

   function Storage_Read_Limits
     (Settings : Improve.Config.Settings) return Improve.Storage.Read_Limits;
   --  Derive hard persistence reconstruction limits from validated configuration.
   --  @param Settings Validated Improve configuration.
   --  @return Limits for one immutable plan revision.

   function Quality_Load_Limits
     (Settings : Improve.Config.Settings) return Ada_Quality.Reporting.Load_Limits;
   --  Derive hard Ada Quality snapshot load limits from validated configuration.
   --  @param Settings Validated Improve configuration.
   --  @return Limits applied before the reporting snapshot is materialized.

   function Planning_Policy
     (Settings : Improve.Config.Settings) return Improve.Planner.Policy;
   --  Translate application configuration into deterministic planning policy.
   --  @param Settings Validated Improve configuration.
   --  @return Planning-only policy.

   function Verification_Policy
     (Settings : Improve.Config.Settings) return Improve.Verification.Policy;
   --  Translate application configuration into verification policy.
   --  @param Settings Validated Improve configuration.
   --  @return Verification-only policy.

   function Refinement_Limits
     (Settings : Improve.Config.Settings) return Improve.Refinement.Limits;
   --  Translate application configuration into bounded refinement inputs.
   --  @param Settings Validated Improve configuration.
   --  @return Refinement-only limits.
end Improve.Operations;
