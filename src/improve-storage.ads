with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Database;
with Database.Schema;
with Improve.Model;

--  Improve-owned durable state. External quality and harness stores are never
--  opened through this package.
package Improve.Storage is
   --  Improve-owned transactional persistence for immutable plans and append-only evidence.

   Current_Schema_Version : constant Positive := 1;
   --  Supported Improve state schema version.

   type Store is limited private;
   --  Open Improve state database handle.

   type Save_Result is record
      Plan     : Improve.Model.Plan_Revision;
      Existing : Boolean := False;
   end record;
   --  Result of idempotent plan persistence.
   --  @field Plan Persisted plan with assigned identities.
   --  @field Existing Whether an identical revision already existed.

   type Plan_Summary is record
      Plan_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Revision    : Positive;
      Project_Id  : Positive;
      Project     : Ada.Strings.Unbounded.Unbounded_String;
      Run_Id      : Positive;
      Task_Count  : Natural;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Latest immutable revision summary.
   --  @field Plan_Id Stable plan identity.
   --  @field Revision Latest revision ordinal.
   --  @field Project_Id Target project identity.
   --  @field Project Target project name.
   --  @field Run_Id Baseline assessment identity.
   --  @field Task_Count Number of remediation tasks.
   --  @field Fingerprint Deterministic revision fingerprint.

   package Summary_Vectors is new Ada.Containers.Vectors (Positive, Plan_Summary);
   --  Ordered plan summaries.

   type Publication_Record is record
      Improve_Task_Id : Ada.Strings.Unbounded.Unbounded_String;
      Harness_Task_Id : Ada.Strings.Unbounded.Unbounded_String;
      Origin          : Ada.Strings.Unbounded.Unbounded_String;
      State           : Ada.Strings.Unbounded.Unbounded_String;
      Plan_Revision   : Positive := 1;
   end record;
   --  Verified mapping from Improve work to a native harness task.
   --  @field Improve_Task_Id Stable Improve task identity.
   --  @field Harness_Task_Id Native model_runner task identity.
   --  @field Origin Authenticated stable Improve origin.
   --  @field State Cached harness-owned runtime state.
   --  @field Plan_Revision Immutable revision that first published the task.

   package Publication_Vectors is new Ada.Containers.Vectors (Positive, Publication_Record);
   --  Ordered publication mappings.

   type Verification_Record is record
      Task_Id      : Ada.Strings.Unbounded.Unbounded_String;
      Assessment_Id : Positive;
      Outcome      : Improve.Model.Quality_Outcome;
      Comparable   : Boolean;
      Explanation  : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Append-only independent verification evidence.
   --  @field Task_Id Improve task identity.
   --  @field Assessment_Id Completed assessment identity.
   --  @field Outcome Quality outcome.
   --  @field Comparable Whether baseline and current evidence are comparable.
   --  @field Explanation Evidence-based conclusion.

   package Verification_Vectors is new Ada.Containers.Vectors (Positive, Verification_Record);
   --  Ordered verification records.

   type Operation_Record is record
      Id       : Positive;
      Key      : Ada.Strings.Unbounded.Unbounded_String;
      Plan_Id  : Ada.Strings.Unbounded.Unbounded_String;
      Revision : Positive;
      Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Task_Ids : Improve.Model.UString_Vectors.Vector;
   end record;
   --  Pending durable publication authorization.
   --  @field Id Journal operation identity.
   --  @field Key Stable idempotency key.
   --  @field Plan_Id Authorized plan identity.
   --  @field Revision Exact authorized immutable revision.
   --  @field Fingerprint Exact authorized revision fingerprint.
   --  @field Task_Ids Exact authorized task identities.

   package Operation_Vectors is new Ada.Containers.Vectors (Positive, Operation_Record);
   --  Ordered pending operations.

   procedure Open (Item : in out Store; Path : String; Writable : Boolean);
   --  Open Improve state. Writable mode creates and initializes a missing
   --  database; read-only mode never creates, migrates, or repairs state.
   --  @param Item Store handle.
   --  @param Path Improve database path.
   --  @param Writable Whether writes and initialization are authorized.

   procedure Close (Item : in out Store);
   --  Close a store; closing an already closed store is harmless.
   --  @param Item Store handle.

   function Save (Item : in out Store; Value : Improve.Model.Plan_Revision) return Save_Result;
   --  Atomically persist a plan revision and its evidence graph. Repeating an
   --  identical fingerprint returns the existing revision.
   --  @param Item Writable store.
   --  @param Value Plan revision to persist.
   --  @return Assigned plan and idempotency result.

   function Load (Item : in out Store; Plan_Id : String) return Improve.Model.Plan_Revision;
   --  Load the latest immutable revision for a plan.
   --  @param Item Open store.
   --  @param Plan_Id Stable plan identity.
   --  @return Latest immutable revision.

   function Load
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive) return Improve.Model.Plan_Revision;
   --  Load one exact immutable plan revision.
   --  @param Item Open store.
   --  @param Plan_Id Stable plan identity.
   --  @param Revision Immutable revision ordinal.
   --  @return Exact plan revision.

   function List
     (Item : in out Store; Project_Id : Natural := 0) return Summary_Vectors.Vector;
   --  List latest plan revisions, optionally filtered by project.
   --  @param Item Open store.
   --  @param Project_Id Project identity or zero for every project.
   --  @return Stable plan summaries.

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector);
   --  Atomically record verified Improve-to-harness mappings. Existing equal
   --  mappings are retained; conflicting reuse is rejected.
   --  @param Item Writable store.
   --  @param Plan_Id Owning plan identity.
   --  @param Values Verified mappings.

   function Publications
     (Item : in out Store; Plan_Id : String := "") return Publication_Vectors.Vector;
   --  Read publication mappings, optionally for one plan.
   --  @param Item Open store.
   --  @param Plan_Id Plan identity or empty for every plan.
   --  @return Publication mappings.

   procedure Update_Publication_States
     (Item   : in out Store;
      Values : Publication_Vectors.Vector);
   --  Update only the cached harness-owned runtime state after validating
   --  that task identity, harness identity, and origin still match.
   --  @param Item Writable store.
   --  @param Values Reconciled mappings and states.

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Verification_Vectors.Vector);
   --  Append independent measurement outcomes in one transaction. Repeating
   --  identical task/assessment evidence is idempotent.
   --  @param Item Writable store.
   --  @param Plan_Id Owning plan identity.
   --  @param Values Verification evidence.

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "") return Verification_Vectors.Vector;
   --  Read historical evidence in insertion order, optionally filtered by
   --  plan and Improve task identity.
   --  @param Item Open store.
   --  @param Plan_Id Plan identity or empty for every plan.
   --  @param Task_Id Task identity or empty for every task.
   --  @return Historical verification records.

   function Begin_Publication
     (Item     : in out Store;
      Plan     : Improve.Model.Plan_Revision;
      Task_Ids : Improve.Model.UString_Vectors.Vector) return Positive;
   --  Durably record deliberate publication authorization before touching
   --  harness state. Repeating the same plan/task set returns the same ID.
   --  @param Item Writable store.
   --  @param Plan Exact authorized immutable plan revision.
   --  @param Task_Ids Exact authorized Improve task identities.
   --  @return Durable operation identity.

   procedure Complete_Publication (Item : in out Store; Operation_Id : Positive);
   --  Append an idempotent completion event after mappings are durable.
   --  @param Item Writable store.
   --  @param Operation_Id Completed publication operation.

   function Pending_Publications (Item : in out Store) return Operation_Vectors.Vector;
   --  Return authorized publication starts with no completion event.
   --  @param Item Open store.
   --  @return Pending publication operations.

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
