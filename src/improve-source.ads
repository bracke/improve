with Ada_Quality.Reporting;
with Improve.Model;

--  Read-only Ada Quality project and completed-assessment selection.
package Improve.Source is
   --  Snapshot-consistent, read-only access to Ada Quality evidence.

   type Repository is limited private;
   --  One immutable Ada Quality reporting snapshot.

   type Selection is record
      Project    : Improve.Model.Project_Reference;
      Assessment : Ada_Quality.Reporting.Assessment_Record;
      Baseline   : Improve.Model.Assessment_Baseline;
   end record;
   --  A validated completed assessment and its immutable provenance.
   --  @field Project Selected registered project.
   --  @field Assessment Complete typed assessment.
   --  @field Baseline Immutable baseline provenance.

   procedure Open
     (Item   : in out Repository;
      Path   : String;
      Limits : Ada_Quality.Reporting.Load_Limits := (others => <>));
   --  Open an existing assessment database through the read-only reporting API.
   --  @param Item Repository handle.
   --  @param Path Existing Ada Quality database path.
   --  @param Limits Bounded reporting load limits.

   procedure Close (Item : in out Repository);
   --  Release the in-memory snapshot.
   --  @param Item Repository handle.

   function Projects (Item : Repository) return Ada_Quality.Reporting.Project_Vectors.Vector;
   --  Return active registry projects in ascending identity order.
   --  @param Item Open repository.
   --  @return Active registered projects.

   function Identity (Item : Repository) return String;
   --  Return the immutable reporting snapshot identity.
   --  @param Item Open repository.
   --  @return Snapshot identity.

   function Resolve_Project (Item : Repository; Selector : String) return Improve.Model.Project_Reference;
   --  Resolve a positive identity, exact canonical path, or unique path basename.
   --  @param Item Open repository.
   --  @param Selector Project identity, path, or unique name.
   --  @return Resolved project reference.

   function Select_Assessment
     (Item       : Repository;
      Project    : Improve.Model.Project_Reference;
      Run_Id     : Natural := 0) return Selection;
   --  Select an explicit completed run or the greatest completed run identity.
   --  @param Item Open repository.
   --  @param Project Resolved project.
   --  @param Run_Id Explicit run identity or zero for latest completed.
   --  @return Validated assessment selection.

   function Working_Fingerprint (Root : String) return String;
   --  Fingerprint the current project source while excluding generated build
   --  directories, runtime databases, and model_runner-owned operational state.
   --  @param Root Canonical project root.
   --  @return Stable source fingerprint used for publication staleness checks.

private
   type Repository is limited record
      Session : Ada_Quality.Reporting.Session;
      Opened  : Boolean := False;
   end record;
end Improve.Source;

