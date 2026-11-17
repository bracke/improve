with Ada.Calendar;
with Ada.Containers.Doubly_Linked_Lists;
with Ada.Containers.Vectors;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Types;
with Database.Predicates;
with Database.Status;
with Database.Storage.File_IO;
with Database.Transactions;
with Database.UUIDs;
with Database.Values;
with Database.WAL;
with Improve.Persistence_Records;
with Improve.Persistence_Validation;
with Improve.Storage.Allocation;
with Improve.Storage_Codec;
with Improve.Storage_Values;

package body Improve.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage_Codec;
   use Improve.Storage_Values;
   use Improve.Persistence_Schema;
   use type Ada.Containers.Count_Type;
   use type Database.Status_Code;
   use type Database.Predicates.Predicate;
   LF : constant Character := Character'Val (10);
   package String_Id_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Positive, Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

   package String_Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Ada.Strings.Unbounded.Unbounded_String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type History_Budget is record
      Limit    : Positive;
      Consumed : Natural := 0;
   end record;

   function New_History_Budget (Limits : Persistence_Limits) return History_Budget is
     (Limit => Limits.Maximum_History, Consumed => 0);

   procedure Consume_History
     (Budget  : in out History_Budget;
      Context : String) is separate;

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Data_Error with Context & ": " & Decode (To_Wide_Wide_String (Status.Message));
      end if;
   end Check;

   procedure Begin_Read_Transaction
     (DB : in out Database.Handle;
      Tx : out Database.Transactions.Transaction) is
   begin
      Database.Transactions.Begin_Read (DB, Tx);
      Check (Database.Transactions.Result (Tx), "begin Improve read transaction");
   end Begin_Read_Transaction;

   procedure Begin_Write_Transaction
     (DB : in out Database.Handle;
      Tx : out Database.Transactions.Transaction) is
   begin
      Database.Transactions.Begin_Write (DB, Tx);
      Check (Database.Transactions.Result (Tx), "begin Improve write transaction");
   end Begin_Write_Transaction;

   procedure Commit_Transaction
     (Tx      : in out Database.Transactions.Transaction;
      Context : String) is
   begin
      Check (Database.Transactions.Commit (Tx), Context);
   end Commit_Transaction;

   procedure Rollback_Transaction
     (Tx      : in out Database.Transactions.Transaction;
      Context : String) is
   begin
      Check (Database.Transactions.Rollback (Tx), Context);
   end Rollback_Transaction;

   function Scan
     (Item      : in out Store;
      Tx        : in out Database.Transactions.Transaction;
      Table     : Positive)
      return Entity_Tables.Cursor is
      Cursor : Entity_Tables.Cursor;
   begin
      Check
        (Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table),
            Database.Predicates.Column_Equals
              (1, Database.Values.From_Integer (Integer (Table))),
            Cursor),
         "scan table");
      return Cursor;
   end Scan;

   procedure Advance
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      Cursor : in out Entity_Tables.Cursor) is
   begin
      Check
        (Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table),
            Database.Predicates.Column_Equals
              (1, Database.Values.From_Integer (Integer (Table))), Cursor),
         "advance table scan");
   end Advance;

   function Child_Predicate (Table, Parent : Positive) return Database.Predicates.Predicate is
     (Database.Predicates.Column_Equals
        (1, Database.Values.From_Integer (Integer (Table))) and
      Database.Predicates.Column_Equals
        (3, Database.Values.From_Integer (Integer (Parent))));

   function Scan_Children
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      Parent : Positive) return Entity_Tables.Cursor is
      Cursor : Entity_Tables.Cursor;
   begin
      Check
        (Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table), Child_Predicate (Table, Parent), Cursor),
         "scan child records");
      return Cursor;
   end Scan_Children;

   procedure Advance_Children
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      Parent : Positive;
      Cursor : in out Entity_Tables.Cursor) is
   begin
      Check
        (Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table), Child_Predicate (Table, Parent), Cursor),
         "advance child record scan");
   end Advance_Children;

   function Kind_Predicate (Table : Positive; Kind : String) return Database.Predicates.Predicate is
     (Database.Predicates.Column_Equals
        (1, Database.Values.From_Integer (Integer (Table))) and
      Database.Predicates.Column_Equals
        (4, Database.Values.From_Text (Encode (Kind))));

   function Scan_Kind
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      Kind  : String) return Entity_Tables.Cursor is
      Cursor : Entity_Tables.Cursor;
   begin
      Check
        (Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table), Kind_Predicate (Table, Kind), Cursor),
         "scan records by kind");
      return Cursor;
   end Scan_Kind;

   procedure Advance_Kind
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      Kind   : String;
      Cursor : in out Entity_Tables.Cursor) is
   begin
      Check
        (Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table), Kind_Predicate (Table, Kind), Cursor),
         "advance kind record scan");
   end Advance_Kind;

   function State_Predicate (Table : Positive; State : String) return Database.Predicates.Predicate is
     (Database.Predicates.Column_Equals
        (1, Database.Values.From_Integer (Integer (Table))) and
      Database.Predicates.Column_Equals
        (5, Database.Values.From_Text (Encode (State))));

   function Scan_State
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      State : String) return Entity_Tables.Cursor is
      Cursor : Entity_Tables.Cursor;
   begin
      Check
        (Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table), State_Predicate (Table, State), Cursor),
         "scan records by state");
      return Cursor;
   end Scan_State;

   procedure Advance_State
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      State  : String;
      Cursor : in out Entity_Tables.Cursor) is
   begin
      Check
        (Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table), State_Predicate (Table, State), Cursor),
         "advance state record scan");
   end Advance_State;

   procedure Migrate_To_Version_3
     (Item     : in out Store;
      Metadata : in out Entity;
      Limits   : Persistence_Limits) is separate;

   procedure Migrate_To_Version_4
     (Item     : in out Store;
      Metadata : in out Entity;
      Limits   : Persistence_Limits) is separate;

   procedure Migrate_To_Version_5
     (Item     : in out Store;
      Metadata : in out Entity;
      Limits   : Persistence_Limits) is separate;

   procedure Migrate_To_Version_6
     (Item     : in out Store;
      Metadata : in out Entity) is separate;

   procedure Migrate_To_Version_7
     (Item     : in out Store;
      Metadata : in out Entity;
      Limits   : Persistence_Limits) is separate;

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Limits   : Persistence_Limits := Default_Persistence_Limits) is separate;

   procedure Close (Item : in out Store) is separate;

   function Identity (Item : Store) return String is separate;

   overriding procedure Finalize (Item : in out Store) is separate;

   function Finding_Payload (Value : Improve.Model.Finding_Reference) return String is
     (Pair ("indicator", Ada_Quality.Types.Image (Value.Indicator)) & LF & Pair ("rule", To_String (Value.Rule)) & LF &
      Pair ("severity", Ada_Quality.Types.Severity'Image (Value.Level)) & LF &
      Pair ("path", To_String (Value.Relative_Path)) & LF & Pair ("line", Number (Value.Line)) & LF &
      Pair ("subject", To_String (Value.Semantic_Subject)) & LF & Pair ("message", To_String (Value.Message)) & LF &
      Pair ("evidence", To_String (Value.Evidence)) & LF &
      Pair ("indicator_level", Boolean_Image (Value.Indicator_Level)));

   function Task_Payload (Value : Improve.Model.Task_Specification) return String is
     (Pair ("draft_id", To_String (Value.Id)) & LF & Pair ("title", To_String (Value.Title)) & LF &
      Pair ("priority", Improve.Model.Image (Value.Task_Priority)) & LF &
      Pair ("files", Pack (Value.Relevant_Files)) & LF & Pair ("scope", To_String (Value.Scope)) & LF &
      Pair ("finding_set", Stable_Digest (Pack (Value.Finding_Keys))) & LF &
      Pair ("confidence", Number (Value.Confidence)) & LF & Pair ("review", Boolean_Image (Value.Requires_Review)));

   function Stored_Finding_Set (Payload : String) return String is
      Current : constant String := Field_Or (Payload, "finding_set", "");
   begin
      if Current /= "" then
         return Current;
      end if;
      return Stable_Digest (Field (Payload, "finding_keys"));
   end Stored_Finding_Set;

   function Task_Identity_Key
     (Category, Title, Acceptance, Finding_Set : String) return String is
     (Stable_Digest
        (Number (Category'Length) & ":" & Category & Number (Title'Length) & ":" & Title &
         Number (Acceptance'Length) & ":" & Acceptance & Number (Finding_Set'Length) & ":" & Finding_Set));

   function Revision_Payload (Value : Improve.Model.Plan_Revision; Baseline_Id, Revision : Positive) return String is
     (Pair ("revision", Number (Revision)) & LF & Pair ("baseline_id", Number (Baseline_Id)) & LF &
      Pair ("project_id", Number (Value.Project.Id)) & LF & Pair ("project", To_String (Value.Project.Name)) & LF &
      Pair ("project_path", To_String (Value.Project.Path)) & LF &
      Pair ("quality_database", To_String (Value.Project.Database_Id)) & LF &
      Pair ("run_id", Number (Value.Baseline.Run_Id)) & LF &
      Pair ("source", To_String (Value.Baseline.Source_Id)) & LF &
      Pair ("working_source", To_String (Value.Working_Source_Id)) & LF &
      Pair ("policy", To_String (Value.Baseline.Policy_Id)) & LF &
      Pair ("toolchain", To_String (Value.Baseline.Toolchain_Id)) & LF &
      Pair ("assessment", To_String (Value.Baseline.Evidence_Id)) & LF &
      Pair ("snapshot", To_String (Value.Baseline.Snapshot_Id)) & LF &
      Pair ("planner", To_String (Value.Planner_Id)) & LF &
      Pair ("task_count", Number (Natural (Value.Tasks.Length))) & LF &
      Pair ("created_at", Timestamp (Value.Created_At)));

   function Find_Revision
     (Item        : in out Store;
      Tx          : in out Database.Transactions.Transaction;
      Fingerprint : String;
      Budget      : in out History_Budget) return Natural is
      Cursor  : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Revisions_Table, Fingerprint);
      Found   : Natural := 0;
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         if Found > 0 then
            raise Data_Error with "duplicate persisted plan revision fingerprint";
         end if;
         Consume_History (Budget, "plan fingerprint history");
         Found := Entity_Tables.Element (Cursor).Id;
         Advance_Kind (Item, Tx, Revisions_Table, Fingerprint, Cursor);
      end loop;
      return Found;
   end Find_Revision;

   function Project_Key (Value : Improve.Model.Project_Reference) return String is
     (Stable_Digest
        (To_String (Value.Database_Id) & Character'Val (0) & Number (Value.Id) & Character'Val (0) &
         To_String (Value.Path)));

   function Legacy_Project_Key (Value : Improve.Model.Project_Reference) return String is separate;

   procedure Require_Idempotent_Equivalent
     (Existing, Candidate : Improve.Model.Plan_Revision) is separate;

   procedure Validate_Save_Value
     (Value  : Improve.Model.Plan_Revision;
      Limits : Persistence_Limits) is separate;

   procedure Consume_Persistence_Row
     (Limits    : Persistence_Limits;
      Kind      : String;
      State     : String;
      Payload   : String;
      Context   : String;
      Total     : in out Natural;
      Operation : String) is separate;

   procedure Index_Previous_Tasks
     (Item              : in out Store;
      Tx                : in out Database.Transactions.Transaction;
      Previous_Revision : Natural;
      Limits            : Persistence_Limits;
      Consumed_Bytes    : in out Natural;
      Previous_Tasks    : in out String_Value_Maps.Map) is separate;

   function Previous_Task_Id
     (Spec           : Improve.Model.Task_Specification;
      Findings       : Improve.Model.Finding_Vectors.Vector;
      Previous_Tasks : String_Value_Maps.Map) return Unbounded_String is separate;

   type Stored_Provenance is record
      Project  : Improve.Model.Project_Reference;
      Baseline : Improve.Model.Assessment_Baseline;
   end record;

   function Provenance_Of
     (Item     : in out Store;
      Tx       : in out Database.Transactions.Transaction;
      Revision : Entity;
      Payload  : String;
      Limits   : Persistence_Limits;
      Consumed_Bytes : in out Natural) return Stored_Provenance is separate;

   function Contract_Key
     (Plan_Id  : String;
      Revision : Positive;
      Task_Id  : String) return String is
     (Plan_Id & Character'Val (0) & Number (Revision) & Character'Val (0) & Task_Id);

   function Load_Revision
     (Item        : in out Store;
      Revision_Id : Positive;
      Limits      : Persistence_Limits) return Improve.Model.Plan_Revision is separate;

   function Load_Exact
     (Item          : in out Store;
      Plan_Id       : String;
      Revision      : Positive;
      Limits        : Persistence_Limits;
      Budget        : in out History_Budget) return Improve.Model.Plan_Revision;

function Save
  (Item   : in out Store;
   Value  : Improve.Model.Plan_Revision;
   Limits : Persistence_Limits := Default_Persistence_Limits) return Save_Result is separate;

   procedure Cache_Contracts
     (Item      : in out Store;
      Plan_Id   : String;
      Revision  : Positive;
      Limits    : Persistence_Limits;
      Budget    : in out History_Budget;
      Contracts : in out String_Value_Maps.Map) is separate;

   function Load
     (Item    : in out Store;
      Plan_Id : String;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision is
      Tx : Database.Transactions.Transaction;
      Revision_Id : Natural := 0;
      Plan_Row : Natural := 0;
      Budget : History_Budget := New_History_Budget (Limits);
   begin
      Plan_Row := Plan_Row_Id (Plan_Id);
      Begin_Read_Transaction (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Consume_History (Budget, "plan revision history");
            if Entity_Tables.Element (Cursor).Parent_Id = Plan_Row then
               Revision_Id := Natural'Max (Revision_Id, Entity_Tables.Element (Cursor).Id);
            end if;
            Advance_Children (Item, Tx, Revisions_Table, Positive (Plan_Row), Cursor);
         end loop;
      end;
      Rollback_Transaction (Tx, "finish latest plan revision query");
      if Revision_Id = 0 then raise Argument_Error with "unknown plan " & Plan_Id; end if;
      return Load_Revision (Item, Positive (Revision_Id), Limits);
   exception
      when Constraint_Error =>
         raise Data_Error with "stored plan revision index is malformed";
   end Load;

   function Load_Exact
     (Item          : in out Store;
      Plan_Id       : String;
      Revision      : Positive;
      Limits        : Persistence_Limits;
      Budget        : in out History_Budget) return Improve.Model.Plan_Revision is
      Tx          : Database.Transactions.Transaction;
      Plan_Row    : Natural := 0;
      Revision_Id : Natural := 0;
   begin
      Plan_Row := Plan_Row_Id (Plan_Id);
      Begin_Read_Transaction (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor :=
        Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            Consume_History (Budget, "plan revision history");
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               Require_Payload_Limit (S (Row.Payload), Limits, "plan revision payload");
               if Row.Parent_Id = Plan_Row and then
                 Positive'Value (Field (S (Row.Payload), "revision")) = Revision
               then
                  Revision_Id := Row.Id;
                  exit;
               end if;
            end;
            Advance_Children (Item, Tx, Revisions_Table, Positive (Plan_Row), Cursor);
         end loop;
      end;
      Rollback_Transaction (Tx, "finish exact plan revision query");
      if Revision_Id = 0 then
         raise Argument_Error with "unknown plan revision " & Plan_Id & " r" & Number (Revision);
      end if;
      return Load_Revision (Item, Positive (Revision_Id), Limits);
   exception
      when Constraint_Error =>
         raise Data_Error with "stored plan revision index is malformed";
   end Load_Exact;

   function Load
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision is
      Budget : History_Budget := New_History_Budget (Limits);
   begin
      return Load_Exact (Item, Plan_Id, Revision, Limits, Budget);
   end Load;

   function Load_Task
     (Item     : in out Store;
      Task_Id  : String;
      Revision : Natural := 0;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Improve.Model.Plan_Revision is separate;

   function Latest_Revision_Id
     (Item     : in out Store;
      Tx       : in out Database.Transactions.Transaction;
      Plan_Row : Positive;
      Budget   : in out History_Budget) return Natural is separate;

   type Stored_Plan_Summary is record
      Value   : Plan_Summary;
      Project : Improve.Model.Project_Reference;
   end record;

   function Summary_Of
     (Item        : in out Store;
      Tx          : in out Database.Transactions.Transaction;
      Revision_Id : Positive;
      Limits      : Persistence_Limits) return Stored_Plan_Summary is separate;

   function List_All
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Summary_Vectors.Vector is separate;

   function List
     (Item    : in out Store;
      Project : Improve.Model.Project_Reference;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Summary_Vectors.Vector is separate;

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector;
      Limits  : Persistence_Limits := Default_Persistence_Limits) is separate;

   procedure Update_Publication_States
     (Item   : in out Store;
      Plan_Id : String;
      Values : Publication_Vectors.Vector;
      Limits : Persistence_Limits := Default_Persistence_Limits) is separate;

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Verification_Vectors.Vector;
      Limits  : Persistence_Limits := Default_Persistence_Limits) is separate;

   package History_Support is
      type Publication_Envelope is record
         Plan_Id : Unbounded_String;
         Value   : Publication_Record;
      end record;

      package Publication_Envelope_Lists is new Ada.Containers.Doubly_Linked_Lists
        (Element_Type => Publication_Envelope);

      type Verification_Envelope is record
         Plan_Id : Unbounded_String;
         Value   : Verification_Record;
      end record;

      package Verification_Envelope_Lists is new Ada.Containers.Doubly_Linked_Lists
        (Element_Type => Verification_Envelope);

      procedure Decode_Publication
        (Item             : Store;
         Row              : Entity;
         Expected_Plan_Id : String;
         Limits           : Persistence_Limits;
         Value            : out Publication_Envelope);

      procedure Decode_Verification
        (Item             : Store;
         Row              : Entity;
         Expected_Plan_Id : String;
         Limits           : Persistence_Limits;
         Value            : out Verification_Envelope);

      procedure Validate_Publications
        (Item     : in out Store;
         Values   : Publication_Envelope_Lists.List;
         Limits   : Persistence_Limits;
         Budget   : in out History_Budget);

      procedure Validate_Verifications
        (Item     : in out Store;
         Values   : Verification_Envelope_Lists.List;
         Limits   : Persistence_Limits;
         Budget   : in out History_Budget);
   end History_Support;

   package body History_Support is separate;

   function Publications
     (Item       : in out Store;
      Plan_Id    : String := "";
      Maximum    : Positive := Default_Query_Maximum;
      Limits     : Persistence_Limits := Default_Persistence_Limits) return Publication_Vectors.Vector is separate;

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "";
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Verification_Vectors.Vector is separate;

   function History
     (Item : in out Store; Plan_Id : String; Revision : Natural := 0;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits;
      Selection : History_Selection := Complete_History) return Inspection_History is separate;

   procedure Approve
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits) is separate;

   function Is_Approved
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Boolean is separate;

   function Begin_Publication
     (Item     : in out Store;
      Plan     : Improve.Model.Plan_Revision;
      Task_Kind : String;
      Task_Ids : Improve.Model.UString_Vectors.Vector;
      Limits   : Persistence_Limits := Default_Persistence_Limits) return Positive is separate;

   procedure Complete_Publication
     (Item         : in out Store;
      Operation_Id : Positive;
      Limits       : Persistence_Limits := Default_Persistence_Limits) is separate;

   function Pending_Publications
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Persistence_Limits := Default_Persistence_Limits) return Operation_Vectors.Vector is separate;
end Improve.Storage;
