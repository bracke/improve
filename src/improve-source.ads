with Ada_Quality.Reporting;
with Improve.Model;

--  Read-only Ada Quality project and completed-assessment selection.
package Improve.Source is
   type Repository is limited private;
   --  One immutable Ada Quality reporting snapshot.

   type Selection is record
      Project    : Improve.Model.Project_Reference;
      Assessment : Ada_Quality.Reporting.Assessment_Record;
      Baseline   : Improve.Model.Assessment_Baseline;
   end record;
   --  A validated completed assessment and its immutable provenance.

   procedure Open
     (Item   : in out Repository;
      Path   : String;
      Limits : Ada_Quality.Reporting.Load_Limits := (others => <>));
   --  Open an existing assessment database through the read-only reporting API.

   procedure Close (Item : in out Repository);
   --  Release the in-memory snapshot.

   function Projects (Item : Repository) return Ada_Quality.Reporting.Project_Vectors.Vector;
   --  Return active registry projects in ascending identity order.

   function Identity (Item : Repository) return String;
   --  Return the immutable reporting snapshot identity.

   function Resolve_Project (Item : Repository; Selector : String) return Improve.Model.Project_Reference;
   --  Resolve a positive identity, exact canonical path, or unique path basename.

   function Select_Assessment
     (Item       : Repository;
      Project    : Improve.Model.Project_Reference;
      Run_Id     : Natural := 0) return Selection;
   --  Select an explicit completed run or the greatest completed run identity.

private
   type Repository is limited record
      Session : Ada_Quality.Reporting.Session;
      Opened  : Boolean := False;
   end record;
end Improve.Source;

