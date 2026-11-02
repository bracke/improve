with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Database;
with Database.Schema;
with Improve.Model;

--  Improve-owned durable state. External quality and harness stores are never
--  opened through this package.
package Improve.Storage is
   Current_Schema_Version : constant Positive := 1;

   type Store is limited private;

   type Save_Result is record
      Plan     : Improve.Model.Plan_Revision;
      Existing : Boolean := False;
   end record;

   type Plan_Summary is record
      Plan_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Revision    : Positive;
      Project_Id  : Positive;
      Project     : Ada.Strings.Unbounded.Unbounded_String;
      Run_Id      : Positive;
      Task_Count  : Natural;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Summary_Vectors is new Ada.Containers.Vectors (Positive, Plan_Summary);

   type Publication_Record is record
      Improve_Task_Id : Ada.Strings.Unbounded.Unbounded_String;
      Harness_Task_Id : Ada.Strings.Unbounded.Unbounded_String;
      Origin          : Ada.Strings.Unbounded.Unbounded_String;
      State           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Publication_Vectors is new Ada.Containers.Vectors (Positive, Publication_Record);

   type Verification_Record is record
      Task_Id      : Ada.Strings.Unbounded.Unbounded_String;
      Assessment_Id : Positive;
      Outcome      : Improve.Model.Quality_Outcome;
      Comparable   : Boolean;
      Explanation  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Verification_Vectors is new Ada.Containers.Vectors (Positive, Verification_Record);

   procedure Open (Item : in out Store; Path : String; Writable : Boolean);
   --  Open Improve state. Writable mode creates and initializes a missing
   --  database; read-only mode never creates, migrates, or repairs state.

   procedure Close (Item : in out Store);

   function Save (Item : in out Store; Value : Improve.Model.Plan_Revision) return Save_Result;
   --  Atomically persist a plan revision and its evidence graph. Repeating an
   --  identical fingerprint returns the existing revision.

   function Load (Item : in out Store; Plan_Id : String) return Improve.Model.Plan_Revision;
   --  Load the latest immutable revision for a plan.

   function List
     (Item : in out Store; Project_Id : Natural := 0) return Summary_Vectors.Vector;
   --  List latest plan revisions, optionally filtered by project.

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector);
   --  Atomically record verified Improve-to-harness mappings. Existing equal
   --  mappings are retained; conflicting reuse is rejected.

   function Publications
     (Item : in out Store; Plan_Id : String := "") return Publication_Vectors.Vector;
   --  Read publication mappings, optionally for one plan.

   procedure Update_Publication_States
     (Item   : in out Store;
      Values : Publication_Vectors.Vector);
   --  Update only the cached harness-owned runtime state after validating
   --  that task identity, harness identity, and origin still match.

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Verification_Vectors.Vector);
   --  Append independent measurement outcomes in one transaction. Repeating
   --  identical task/assessment evidence is idempotent.

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "") return Verification_Vectors.Vector;
   --  Read historical evidence in insertion order, optionally filtered by
   --  plan and Improve task identity.

private
   Logical_Table_Count : constant := 12;
   type Schema_Array is array (Positive range 1 .. Logical_Table_Count) of Database.Schema.Table_Schema;

   type Store is limited record
      DB       : Database.Handle;
      Schemas  : Schema_Array;
      Opened   : Boolean := False;
      Writable : Boolean := False;
   end record;
end Improve.Storage;
