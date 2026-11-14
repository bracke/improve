with Ada.Calendar;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Directories;
with Ada.Strings.Hash;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Types;
with Database.Predicates;
with Database.Rows;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Improve.Persistence_Records;
with Improve.Persistence_Validation;
with Improve.Storage_Codec;
with Interfaces;

package body Improve.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Improve.Storage_Codec;
   use type Ada.Containers.Count_Type;
   use type Database.Status_Code;
   use type Database.Predicates.Predicate;
   LF : constant Character := Character'Val (10);
   Schema_Metadata_Table     : constant Positive := 1;
   Projects_Table            : constant Positive := 2;
   Baselines_Table           : constant Positive := 3;
   Findings_Table            : constant Positive := 4;
   Plans_Table               : constant Positive := 5;
   Revisions_Table           : constant Positive := 6;
   Tasks_Table               : constant Positive := 7;
   Task_Findings_Table       : constant Positive := 8;
   Task_Dependencies_Table   : constant Positive := 9;
   Publications_Table        : constant Positive := 10;
   Verifications_Table       : constant Positive := 11;
   Operations_Table          : constant Positive := 12;
   Task_Details_Table        : constant Positive := 13;
   Task_Identities_Table     : constant Positive := 14;
   Namespace_Stride          : constant Positive := 100_000_000;
   Maximum_Logical_Id        : constant Positive := Namespace_Stride;

   Table_Names : constant array (Positive range 1 .. Logical_Table_Count) of access constant Wide_Wide_String :=
     [new Wide_Wide_String'("schema_metadata"), new Wide_Wide_String'("projects"),
      new Wide_Wide_String'("assessment_baselines"), new Wide_Wide_String'("finding_references"),
      new Wide_Wide_String'("plans"), new Wide_Wide_String'("plan_revisions"),
      new Wide_Wide_String'("remediation_tasks"), new Wide_Wide_String'("task_finding_links"),
      new Wide_Wide_String'("task_dependencies"), new Wide_Wide_String'("publications"),
      new Wide_Wide_String'("verification_records"), new Wide_Wide_String'("operations"),
      new Wide_Wide_String'("task_details"), new Wide_Wide_String'("task_identities")];

   function Logical_Table_List return String is
      Result : Unbounded_String;
   begin
      for Table in Table_Names'Range loop
         if Table > Table_Names'First then Append (Result, ","); end if;
         Append (Result, Decode (Table_Names (Table).all));
      end loop;
      return To_String (Result);
   end Logical_Table_List;

   type Entity is record
      Id        : Positive;
      Parent_Id : Natural := 0;
      Kind      : Unbounded_Wide_Wide_String;
      State     : Unbounded_Wide_Wide_String;
      Payload   : Unbounded_Wide_Wide_String;
      Active    : Boolean := True;
      Table_Id  : Positive := 1;
   end record;

   function Physical_Key (Table, Id : Positive) return Positive is
   begin
      if Table > Logical_Table_Count then
         raise Data_Error with "stored namespace identity is outside the Improve schema";
      elsif Id > Maximum_Logical_Id then
         raise Data_Error with "Improve logical identity space is exhausted";
      end if;
      return (Table - 1) * Namespace_Stride + Id;
   end Physical_Key;

   function To_Row (Item : Entity) return Database.Rows.Row is
      Result : Database.Rows.Row;
   begin
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Physical_Key (Item.Table_Id, Item.Id))));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Item.Table_Id)));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Item.Id)));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Item.Parent_Id)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.Kind)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.State)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.Payload)));
      Database.Rows.Append (Result, Database.Values.From_Boolean (Item.Active));
      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Entity is
      Stored_Key : constant Positive := Positive (Database.Rows.Get (Row, 0).Int);
      Table      : constant Positive := Positive (Database.Rows.Get (Row, 1).Int);
      Id         : constant Positive := Positive (Database.Rows.Get (Row, 2).Int);
   begin
      if Stored_Key /= Physical_Key (Table, Id) then
         raise Data_Error with "stored Improve physical identity is inconsistent";
      end if;
      return
        (Id        => Id,
         Parent_Id => Natural (Database.Rows.Get (Row, 3).Int),
         Kind      => Database.Rows.Get (Row, 4).Text,
         State     => Database.Rows.Get (Row, 5).Text,
         Payload   => Database.Rows.Get (Row, 6).Text,
         Active    => Database.Rows.Get (Row, 7).Bool,
         Table_Id  => Table);
   exception
      when Constraint_Error =>
         raise Data_Error with "stored Improve physical identity is malformed";
   end From_Row;

   function Key_Of (Item : Entity) return Positive is (Physical_Key (Item.Table_Id, Item.Id));
   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));

   package Entity_Tables is new Database.Tables.Typed
     (Entity, Positive, To_Row, From_Row, Key_Of, Key_Value);

   package String_Id_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Positive, Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

   package String_Value_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Ada.Strings.Unbounded.Unbounded_String,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String (Name);
      Database.Schema.Add_Column (Result, "physical_id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (Result, "table_id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "parent_id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "kind", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "state", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "payload", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "active", Database.Types.Boolean_Value, False);
      return Result;
   end New_Schema;

   procedure Check (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Data_Error with Context & ": " & Decode (To_Wide_Wide_String (Status.Message));
      end if;
   end Check;

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

   function Next_Id
     (Item : in out Store; Tx : in out Database.Transactions.Transaction; Table : Positive) return Positive is
      Result : Positive;
   begin
      if Item.Next_Ids (Table) = 0 then
         declare
            Cursor  : Entity_Tables.Cursor := Scan (Item, Tx, Table);
            Highest : Natural := 0;
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               Highest := Natural'Max (Highest, Entity_Tables.Element (Cursor).Id);
               Advance (Item, Tx, Table, Cursor);
            end loop;
            if Highest >= Maximum_Logical_Id then
               raise Data_Error with "Improve logical identity space is exhausted";
            end if;
            Item.Next_Ids (Table) := Highest + 1;
         end;
      end if;
      if Item.Next_Ids (Table) > Maximum_Logical_Id then
         raise Data_Error with "Improve logical identity space is exhausted";
      end if;
      Result := Positive (Item.Next_Ids (Table));
      Item.Next_Ids (Table) := Item.Next_Ids (Table) + 1;
      return Result;
   end Next_Id;

   function Reserve_Ids
     (Item  : in out Store;
      Tx    : in out Database.Transactions.Transaction;
      Table : Positive;
      Count : Natural) return Positive is
      First : constant Positive := Next_Id (Item, Tx, Table);
      Reserved : constant Natural := Natural'Max (1, Count);
   begin
      if Reserved - 1 > Maximum_Logical_Id - First then
         raise Data_Error with "Improve logical identity space is exhausted";
      end if;
      Item.Next_Ids (Table) := Item.Next_Ids (Table) + Reserved - 1;
      return First;
   end Reserve_Ids;

   procedure Migrate_To_Version_3
     (Item     : in out Store;
      Metadata : in out Entity) is separate;

   procedure Migrate_To_Version_4
     (Item     : in out Store;
      Metadata : in out Entity) is separate;

   procedure Migrate_To_Version_5
     (Item     : in out Store;
      Metadata : in out Entity;
      Limits   : Read_Limits) is separate;

   procedure Open
     (Item     : in out Store;
      Path     : String;
      Writable : Boolean;
      Limits   : Read_Limits := Default_Read_Limits) is separate;

   procedure Close (Item : in out Store) is
   begin
      if Item.Opened then Database.Close (Item.DB); end if;
      Item.Opened := False;
      Item.Writable := False;
      Item.Schema_Version := 0;
      Item.Next_Ids := [others => 0];
   end Close;

   overriding procedure Finalize (Item : in out Store) is
   begin
      Close (Item);
   exception
      when others => null;
   end Finalize;

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
      Pair ("snapshot", To_String (Value.Baseline.Snapshot_Id)) & LF &
      Pair ("planner", To_String (Value.Planner_Id)) & LF &
      Pair ("task_count", Number (Natural (Value.Tasks.Length))) & LF &
      Pair ("created_at", Timestamp (Value.Created_At)));

   function Find_Revision
     (Item : in out Store; Tx : in out Database.Transactions.Transaction; Fingerprint : String) return Natural is
      Cursor : constant Entity_Tables.Cursor := Scan_Kind (Item, Tx, Revisions_Table, Fingerprint);
   begin
      return (if Entity_Tables.Has_Element (Cursor) then Entity_Tables.Element (Cursor).Id else 0);
   end Find_Revision;

   function Project_Key (Value : Improve.Model.Project_Reference) return String is
     (Stable_Digest
        (To_String (Value.Database_Id) & Character'Val (0) & Number (Value.Id) & Character'Val (0) &
         To_String (Value.Path)));

   function Legacy_Project_Key (Value : Improve.Model.Project_Reference) return String is
      use type Interfaces.Unsigned_64;
      Text : constant String :=
        To_String (Value.Database_Id) & Character'Val (0) & Number (Value.Id) & Character'Val (0) &
        To_String (Value.Path);
      Hash : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Hex  : constant String := "0123456789abcdef";
      Result : String (1 .. 24) := "fnv1a64:0000000000000000";
   begin
      for Byte of Text loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (Byte))) * 16#100000001B3#;
      end loop;
      for Index in reverse 9 .. Result'Last loop
         Result (Index) := Hex (Natural (Hash and 16#F#) + 1);
         Hash := Interfaces.Shift_Right (Hash, 4);
      end loop;
      return Result;
   end Legacy_Project_Key;

function Save
  (Item   : in out Store;
   Value  : Improve.Model.Plan_Revision;
   Limits : Read_Limits := Default_Read_Limits) return Save_Result is separate;

   function Priority_Value (Text : String) return Improve.Model.Priority is
   begin
      for Value in Improve.Model.Priority loop
         if Improve.Model.Image (Value) = Text then return Value; end if;
      end loop;
      raise Data_Error with "invalid persisted priority " & Text;
   end Priority_Value;

   function Kind_Value (Text : String) return Improve.Model.Candidate_Kind is
   begin
      for Value in Improve.Model.Candidate_Kind loop
         if Improve.Model.Image (Value) = Text then return Value; end if;
      end loop;
      raise Data_Error with "invalid persisted candidate kind " & Text;
   end Kind_Value;

   function Indicator_Value (Text : String) return Ada_Quality.Types.Indicator_Id is
   begin
      for Value in Ada_Quality.Types.Indicator_Id loop
         if Ada_Quality.Types.Image (Value) = Text then return Value; end if;
      end loop;
      raise Data_Error with "invalid persisted indicator " & Text;
   end Indicator_Value;

   procedure Require_Payload_Limit
     (Text    : String;
      Limits  : Read_Limits;
      Context : String) is
   begin
      if Text'Length > Limits.Maximum_Text_Bytes then
         raise Data_Error with Context & " exceeds configured persisted-text limit";
      end if;
   end Require_Payload_Limit;

   type Stored_Provenance is record
      Project  : Improve.Model.Project_Reference;
      Baseline : Improve.Model.Assessment_Baseline;
   end record;

   function Provenance_Of
     (Item     : in out Store;
      Tx       : in out Database.Transactions.Transaction;
      Revision : Entity;
      Payload  : String;
      Limits   : Read_Limits) return Stored_Provenance is separate;

   function Contract_Key (Revision : Positive; Task_Id : String) return String is
     (Number (Revision) & Character'Val (0) & Task_Id);

   procedure Cache_Contracts
     (Item      : in out Store;
      Plan_Id   : String;
      Revision  : Positive;
      Limits    : Read_Limits;
      Contracts : in out String_Value_Maps.Map) is separate;

   function Load_Revision
     (Item        : in out Store;
      Revision_Id : Positive;
      Limits      : Read_Limits) return Improve.Model.Plan_Revision is separate;

   function Load
     (Item    : in out Store;
      Plan_Id : String;
      Limits  : Read_Limits := Default_Read_Limits) return Improve.Model.Plan_Revision is
      Tx : Database.Transactions.Transaction;
      Revision_Id : Natural := 0;
      Plan_Row : Natural := 0;
      History_Count : Natural := 0;
   begin
      if Plan_Id'Length > 10 and then Plan_Id (Plan_Id'First .. Plan_Id'First + 9) = "@revision:" then
         declare
            Revision_Id : Positive;
         begin
            begin
               Revision_Id := Positive'Value (Plan_Id (Plan_Id'First + 10 .. Plan_Id'Last));
            exception
               when Constraint_Error => raise Argument_Error with "invalid internal plan revision identity";
            end;
            return Load_Revision (Item, Revision_Id, Limits);
         end;
      end if;
      Plan_Row := Plan_Row_Id (Plan_Id);
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if History_Count >= Limits.Maximum_History then
               raise Data_Error with "plan revision history exceeds configured item limit";
            end if;
            History_Count := History_Count + 1;
            if Entity_Tables.Element (Cursor).Parent_Id = Plan_Row then
               Revision_Id := Natural'Max (Revision_Id, Entity_Tables.Element (Cursor).Id);
            end if;
            Advance_Children (Item, Tx, Revisions_Table, Positive (Plan_Row), Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then raise Argument_Error with "unknown plan " & Plan_Id; end if;
      return Load_Revision (Item, Positive (Revision_Id), Limits);
   exception
      when Constraint_Error =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise Data_Error with "stored plan revision index is malformed";
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load;

   function Load
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Read_Limits := Default_Read_Limits) return Improve.Model.Plan_Revision is
      Tx          : Database.Transactions.Transaction;
      Plan_Row    : Natural := 0;
      Revision_Id : Natural := 0;
      History_Count : Natural := 0;
   begin
      Plan_Row := Plan_Row_Id (Plan_Id);
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor :=
        Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if History_Count >= Limits.Maximum_History then
               raise Data_Error with "plan revision history exceeds configured item limit";
            end if;
            History_Count := History_Count + 1;
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
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then
         raise Argument_Error with "unknown plan revision " & Plan_Id & " r" & Number (Revision);
      end if;
      return Load_Revision (Item, Positive (Revision_Id), Limits);
   exception
      when Constraint_Error =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise Data_Error with "stored plan revision index is malformed";
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load;

   function Load_Task
     (Item     : in out Store;
      Task_Id  : String;
      Revision : Natural := 0;
      Limits   : Read_Limits := Default_Read_Limits) return Improve.Model.Plan_Revision is separate;

   function Latest_Revision_Id
     (Item     : in out Store;
      Tx       : in out Database.Transactions.Transaction;
      Plan_Row : Positive;
      Maximum  : Positive;
      Scanned  : in out Natural) return Natural is separate;

   function Summary_Of
     (Item        : in out Store;
      Tx          : in out Database.Transactions.Transaction;
      Revision_Id : Positive;
      Limits      : Read_Limits) return Plan_Summary is separate;

   function List_All
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Read_Limits := Default_Read_Limits) return Summary_Vectors.Vector is separate;

   function List
     (Item    : in out Store;
      Project : Improve.Model.Project_Reference;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Read_Limits := Default_Read_Limits) return Summary_Vectors.Vector is separate;

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector;
      Limits  : Read_Limits := Default_Read_Limits) is separate;

   function Publications
     (Item       : in out Store;
      Plan_Id    : String := "";
      Maximum    : Positive := Default_Query_Maximum;
      Limits     : Read_Limits := Default_Read_Limits) return Publication_Vectors.Vector is separate;

   procedure Update_Publication_States
     (Item   : in out Store;
      Plan_Id : String;
      Values : Publication_Vectors.Vector;
      Limits : Read_Limits := Default_Read_Limits) is separate;

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Verification_Vectors.Vector;
      Limits  : Read_Limits := Default_Read_Limits) is separate;

   function Parse_Outcome (Value : String) return Improve.Model.Quality_Outcome is
   begin
      for Outcome in Improve.Model.Quality_Outcome loop
         if Improve.Model.Image (Outcome) = Value then return Outcome; end if;
      end loop;
      raise Data_Error with "stored verification outcome is invalid: " & Value;
   end Parse_Outcome;

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "";
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Read_Limits := Default_Read_Limits) return Verification_Vectors.Vector is separate;

   procedure Approve
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Read_Limits := Default_Read_Limits) is separate;

   function Is_Approved
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Read_Limits := Default_Read_Limits) return Boolean is separate;

   function Begin_Publication
     (Item     : in out Store;
      Plan     : Improve.Model.Plan_Revision;
      Task_Kind : String;
      Task_Ids : Improve.Model.UString_Vectors.Vector;
      Limits   : Read_Limits := Default_Read_Limits) return Positive is separate;

   procedure Complete_Publication
     (Item         : in out Store;
      Operation_Id : Positive;
      Limits       : Read_Limits := Default_Read_Limits) is separate;

   function Pending_Publications
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Read_Limits := Default_Read_Limits) return Operation_Vectors.Vector is separate;
end Improve.Storage;
