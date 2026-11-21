with Ada.Finalization;
with Ada.Strings.Unbounded;
with Database;
with Database.Schema;
with Improve.Model;
with Improve.State;
private with Improve.Persistence_Schema;

--  Improve-owned durable state. External quality and harness stores are never
--  opened through this package.
package Improve.Storage is
   --  Improve-owned transactional persistence for immutable plans and append-only evidence.

   Current_Schema_Version : constant Positive := 8;
   --  Supported Improve state schema version.

   type Store is limited private;
   --  Open Improve state database handle.

   type Persistence_Limits is record
      Maximum_Findings          : Positive := 10_000;
      Maximum_Tasks             : Positive := 1_000;
      Maximum_Task_Details      : Positive := 10_000;
      Maximum_Task_Associations : Positive := 50_000;
      Maximum_History           : Positive := 10_000;
      Maximum_Migration_Rows    : Positive := 1_000_000;
      Maximum_Text_Bytes        : Positive := 1_024;
      Maximum_Total_Bytes       : Positive := 67_108_864;
   end record;
   --  Hard limits applied to persistence operations and state-schema migration.
   --  @field Maximum_Findings Maximum findings reconstructed from one revision.
   --  @field Maximum_Tasks Maximum task specifications reconstructed from one revision.
   --  @field Maximum_Task_Details Maximum task-detail records reconstructed from one revision.
   --  @field Maximum_Task_Associations Maximum relevant-file, finding, and dependency associations in one revision.
   --  @field Maximum_History Maximum persisted history records examined or appended by one operation.
   --  @field Maximum_Migration_Rows Maximum rows scanned while upgrading one state database.
   --  @field Maximum_Text_Bytes Maximum encoded bytes accepted from one persisted payload.
   --  @field Maximum_Total_Bytes Maximum aggregate encoded row bytes read or written for one plan revision.

   Default_Persistence_Limits : constant Persistence_Limits := (others => <>);
   --  Conservative limits for callers without validated configuration.

   Default_Query_Maximum  : constant Positive := 10_000;
   --  Maximum records materialized by a default history or summary query.

   type Save_Result is record
      Plan     : Improve.Model.Plan_Revision;
      Existing : Boolean := False;
   end record;
   --  Result of idempotent plan persistence.
   --  @field Plan Persisted plan with assigned identities.
   --  @field Existing Whether an identical revision already existed.

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Limits   : Persistence_Limits := Default_Persistence_Limits);
   --  Open Improve state. Writable mode creates and initializes a missing
   --  database; read-only mode never creates, migrates, or repairs state.
   --  @param Item Store handle.
   --  @param Path Improve database path.
   --  @param Writable Whether writes and initialization are authorized.
   --  @param Limits Hard limits applied to any required schema migration.

   procedure Close (Item : in out Store);
   --  Close a store; closing an already closed store is harmless. A dependency
   --  persistence or handle-close failure raises Data_Error.
   --  @param Item Store handle.

   function Identity (Item : Store) return String;
   --  Return the persistent UUID of this Improve state store, or empty for a legacy read-only store.
   --  @param Item Open store.
   --  @return Persistent state-store identity.

   function Save
     (Item   : in out Store;
      Value  : Improve.Model.Plan_Revision;
      Limits : Persistence_Limits := Default_Persistence_Limits) return Save_Result;
   --  Atomically persist a plan revision and its evidence graph. Repeating an
   --  identical fingerprint returns the existing revision.
   --  @param Item Writable store.
   --  @param Value Plan revision to persist.
   --  @param Limits Hard limits enforced before any state is written.
   --  @return Assigned plan and idempotency result.

   function Load
     (Item    : in out Store;
      Plan_Id : String;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision;
   --  Load the latest immutable revision for a plan.
   --  @param Item Open store.
   --  @param Plan_Id Stable plan identity.
   --  @param Limits Hard reconstruction limits.
   --  @return Latest immutable revision.

   function Load
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision;
   --  Load one exact immutable plan revision.
   --  @param Item Open store.
   --  @param Plan_Id Stable plan identity.
   --  @param Revision Immutable revision ordinal.
   --  @param Limits Hard reconstruction limits.
   --  @return Exact plan revision.

   function Load_Task
     (Item     : in out Store;
      Task_Id  : String;
      Revision : Natural := 0;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision;
   --  Load the newest immutable revision containing a logical task, or an
   --  explicitly selected revision containing it.
   --  @param Item Open store.
   --  @param Task_Id Stable Improve task identity.
   --  @param Revision Exact revision ordinal, or zero for the newest containing revision.
   --  @param Limits Hard reconstruction limits.
   --  @return Immutable plan revision containing the requested task.

   function List_All
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Improve.State.Summary_Vectors.Vector;
   --  List latest plan revisions across all database-qualified projects.
   --  @param Item Open store.
   --  @param Maximum Maximum summaries to materialize.
   --  @param Limits Hard provenance and task-count limits.
   --  @return Stable plan summaries.

   function List
     (Item    : in out Store;
      Project : Improve.Model.Project_Reference;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Improve.State.Summary_Vectors.Vector;
   --  List latest plans for one database-qualified Ada Quality project.
   --  @param Item Open store.
   --  @param Project Full project identity including database and canonical path.
   --  @param Maximum Maximum summaries to materialize.
   --  @param Limits Hard provenance and task-count limits.
   --  @return Stable plan summaries isolated from equal numeric IDs in other databases.

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Improve.State.Publication_Vectors.Vector;
      Limits  : Persistence_Limits := Default_Persistence_Limits);
   --  Atomically record verified Improve-to-harness mappings. Existing equal
   --  mappings are retained; conflicting reuse is rejected.
   --  @param Item Writable store.
   --  @param Plan_Id Owning plan identity.
   --  @param Values Verified mappings.
   --  @param Limits Hard contract and history limits.

   function Publications
     (Item       : in out Store;
      Plan_Id    : String := "";
      Maximum    : Positive := Default_Query_Maximum;
      Limits     : Persistence_Limits := Default_Persistence_Limits) return Improve.State.Publication_Vectors.Vector;
   --  Read publication mappings, optionally for one plan.
   --  @param Item Open store.
   --  @param Plan_Id Plan identity or empty for every plan.
   --  @param Maximum Maximum mappings to materialize.
   --  @param Limits Hard limits for each mapping payload.
   --  @return Publication mappings.

   procedure Update_Publication_States
     (Item   : in out Store;
      Plan_Id : String;
      Values : Improve.State.Publication_Vectors.Vector;
      Limits : Persistence_Limits := Default_Persistence_Limits);
   --  Update only the cached harness-owned runtime state after validating
   --  that task identity, harness identity, and origin still match.
   --  @param Item Writable store.
   --  @param Plan_Id Owning plan identity.
   --  @param Values Reconciled mappings and states.
   --  @param Limits Hard mapping and history limits.

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Improve.State.Verification_Vectors.Vector;
      Limits  : Persistence_Limits := Default_Persistence_Limits);
   --  Append independent measurement outcomes in one transaction. Repeating
   --  identical task/assessment evidence is idempotent.
   --  @param Item Writable store.
   --  @param Plan_Id Owning plan identity.
   --  @param Values Verification evidence.
   --  @param Limits Hard contract and history limits.

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "";
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Improve.State.Verification_Vectors.Vector;
   --  Read historical evidence in insertion order, optionally filtered by
   --  plan and Improve task identity.
   --  @param Item Open store.
   --  @param Plan_Id Plan identity or empty for every plan.
   --  @param Task_Id Task identity or empty for every task.
   --  @param Maximum Maximum evidence records to materialize.
   --  @param Limits Hard limits for each evidence payload.
   --  @return Historical verification records.

   type History_Selection is (Complete_History, Publication_History, Verification_History);
   --  History collections to decode for one consistent inspection snapshot.
   --  @enum Complete_History Decode publication and verification records.
   --  @enum Publication_History Decode only publication records.
   --  @enum Verification_History Decode only verification records.

   function History
     (Item    : in out Store;
      Plan_Id : String;
      Revision : Natural := 0;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits;
      Selection : History_Selection := Complete_History) return Improve.State.Inspection_History;
   --  Read publication and verification history in one database transaction.
   --  @param Item Open store.
   --  @param Plan_Id Owning plan identity.
   --  @param Revision Exact revision to select, or zero for the latest visible revision.
   --  @param Maximum Maximum records of each kind to materialize.
   --  @param Limits Hard limits for persisted history and payloads.
   --  @param Selection Collections to decode; omitted collections are returned empty.
   --  @return Consistent joined-history snapshot.

   procedure Approve
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits);
   --  Append an idempotent approval for one exact immutable plan revision.
   --  Approval never transfers to a different revision or fingerprint.
   --  @param Item Writable store.
   --  @param Plan_Id Stable plan identity.
   --  @param Revision Exact immutable revision to approve.
   --  @param Limits Hard reconstruction limits.

   function Is_Approved
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Boolean;
   --  Test whether one exact immutable plan revision has durable approval.
   --  @param Item Open store.
   --  @param Plan_Id Stable plan identity.
   --  @param Revision Exact immutable revision to inspect.
   --  @param Limits Hard reconstruction limits.
   --  @return True only for an approval matching the revision fingerprint.

   function Begin_Publication
     (Item     : in out Store;
      Plan     : Improve.Model.Plan_Revision;
      Task_Kind : String;
      Task_Ids : Improve.Model.UString_Vectors.Vector;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Positive;
   --  Durably record deliberate publication authorization before touching
   --  harness state. Repeating the same plan/task set returns the same ID.
   --  @param Item Writable store.
   --  @param Plan Exact authorized immutable plan revision.
   --  @param Task_Kind Exact resolved native task kind authorized by preflight.
   --  @param Task_Ids Exact authorized Improve task identities.
   --  @param Limits Hard reconstruction limits.
   --  @return Durable operation identity.

   procedure Complete_Publication
     (Item         : in out Store;
      Operation_Id : Positive;
      Limits       : Persistence_Limits := Default_Persistence_Limits);
   --  Append an idempotent completion event after mappings are durable.
   --  @param Item Writable store.
   --  @param Operation_Id Completed publication operation.
   --  @param Limits Hard operation-history and payload limits.

   function Pending_Publications
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits)
      return Improve.State.Publication_Operation_Vectors.Vector;
   --  Return authorized publication starts with no completion event.
   --  @param Item Open store.
   --  @param Maximum Maximum pending operations to materialize.
   --  @param Limits Hard limits for each recovered operation payload.
   --  @return Pending publication operations.

private
   subtype Persistence_Entity is Improve.Persistence_Schema.Entity;
   function Persistence_Physical_Key (Table, Id : Positive) return Positive
     renames Improve.Persistence_Schema.Physical_Key;
   --  Map one logical namespace identity to its physical key.
   --  @param Table Logical namespace.
   --  @param Id Logical row identity.
   --  @return Collision-free physical key.
   package Persistence_Entity_Tables renames Improve.Persistence_Schema.Entity_Tables;
   function Persistence_New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema
     renames Improve.Persistence_Schema.New_Schema;
   --  Build the private shared persistence schema.
   --  @param Name Physical table name.
   --  @return Canonical shared-table schema.

   Schema_Metadata_Table : constant Positive := Improve.Persistence_Schema.Schema_Metadata_Table;
   Projects_Table        : constant Positive := Improve.Persistence_Schema.Projects_Table;
   Baselines_Table       : constant Positive := Improve.Persistence_Schema.Baselines_Table;
   Revisions_Table       : constant Positive := Improve.Persistence_Schema.Revisions_Table;
   Plans_Table           : constant Positive := Improve.Persistence_Schema.Plans_Table;
   Tasks_Table           : constant Positive := Improve.Persistence_Schema.Tasks_Table;
   Task_Findings_Table   : constant Positive := Improve.Persistence_Schema.Task_Findings_Table;
   Task_Details_Table    : constant Positive := Improve.Persistence_Schema.Task_Details_Table;
   Task_Identities_Table : constant Positive := Improve.Persistence_Schema.Task_Identities_Table;
   Publications_Table    : constant Positive := Improve.Persistence_Schema.Publications_Table;
   Verifications_Table   : constant Positive := Improve.Persistence_Schema.Verifications_Table;

   subtype Plan_Summary is Improve.State.Plan_Summary;
   package Summary_Vectors renames Improve.State.Summary_Vectors;
   subtype Publication_Record is Improve.State.Publication_Record;
   package Publication_Vectors renames Improve.State.Publication_Vectors;
   subtype Verification_Record is Improve.State.Verification_Record;
   package Verification_Vectors renames Improve.State.Verification_Vectors;
   subtype Inspection_History is Improve.State.Inspection_History;
   subtype Operation_Record is Improve.State.Publication_Operation;
   package Operation_Vectors renames Improve.State.Publication_Operation_Vectors;

   Logical_Table_Count : constant := Improve.Persistence_Schema.Logical_Table_Count;
   Maximum_Logical_Id  : constant := Improve.Persistence_Schema.Maximum_Logical_Id;
   type Schema_Array is array (Positive range 1 .. Logical_Table_Count) of Database.Schema.Table_Schema;
   type Id_Array is array (Positive range 1 .. Logical_Table_Count) of Natural;
   type Dirty_Array is array (Positive range 1 .. Logical_Table_Count) of Boolean;

   type Store is new Ada.Finalization.Limited_Controlled with record
      DB       : Database.Handle;
      Schemas  : Schema_Array;
      Next_Ids : Id_Array := [others => 0];
      Dirty_Ids : Dirty_Array := [others => False];
      Opened   : Boolean := False;
      Writable : Boolean := False;
      Schema_Version : Natural := 0;
      Store_Id : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   overriding procedure Finalize (Item : in out Store);
   --  Close an open database during scope finalization or exception unwinding.
   --  @param Item Store whose owned database handle is released.
end Improve.Storage;
