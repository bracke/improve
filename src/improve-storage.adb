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
     ((Table - 1) * 100_000_000 + Id);

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
     ((Id        => Positive (Database.Rows.Get (Row, 2).Int),
       Parent_Id => Natural (Database.Rows.Get (Row, 3).Int),
       Kind      => Database.Rows.Get (Row, 4).Text,
       State     => Database.Rows.Get (Row, 5).Text,
       Payload   => Database.Rows.Get (Row, 6).Text,
       Active    => Database.Rows.Get (Row, 7).Bool,
       Table_Id  => Positive (Database.Rows.Get (Row, 1).Int)));

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
            Item.Next_Ids (Table) := Highest + 1;
         end;
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
   begin
      Item.Next_Ids (Table) := Item.Next_Ids (Table) + Natural'Max (1, Count) - 1;
      return First;
   end Reserve_Ids;

   procedure Migrate_To_Version_3
     (Item     : in out Store;
      Metadata : in out Entity) is
      package Entity_Vectors is new Ada.Containers.Vectors (Positive, Entity);
      Tx      : Database.Transactions.Transaction;
      Pending : Entity_Vectors.Vector;

      procedure Backfill_Parents (Table : Positive) is
         Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Table);
      begin
         Pending.Clear;
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Parent_Id = 0 then Pending.Append (Row); end if;
            end;
            Advance (Item, Tx, Table, Cursor);
         end loop;
         for Row of Pending loop
            declare Updated : Entity := Row; begin
               Updated.Parent_Id := Plan_Row_Id (Field (S (Row.Payload), "plan_id"));
               Check
                 (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Updated),
                  "backfill indexed plan relationship");
            end;
         end loop;
      end Backfill_Parents;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Backfill_Parents (Publications_Table);
      Backfill_Parents (Verifications_Table);
      Metadata.State := WW ("3");
      Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
      Check
        (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
         "migrate Improve schema metadata");
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Migrate_To_Version_3;

   procedure Migrate_To_Version_4
     (Item     : in out Store;
      Metadata : in out Entity) is
      Tx : Database.Transactions.Transaction;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
         while Entity_Tables.Has_Element (Tasks) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Tasks);
               Payload : constant String := S (Row.Payload);
               Task_Id : constant String := Field_Or (Payload, "draft_id", "");
            begin
               if Task_Id /= "" then
                  Check
                    (Entity_Tables.Insert
                       (Tx, Item.DB, Item.Schemas (Task_Identities_Table),
                        (Next_Id (Item, Tx, Task_Identities_Table), Row.Parent_Id,
                         WW (Task_Id), WW ("active"), WW (Pair ("task_row", Number (Row.Id))),
                         True, Task_Identities_Table)),
                     "backfill task identity");
               end if;
            end;
            Advance (Item, Tx, Tasks_Table, Tasks);
         end loop;
      end;
      Metadata.State := WW ("4");
      Metadata.Payload := WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List);
      Check
        (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table), Metadata),
         "migrate task identity index");
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Migrate_To_Version_4;

   procedure Open (Item : in out Store; Path : String; Writable : Boolean) is
      Exists : constant Boolean := Ada.Directories.Exists (Path);
   begin
      if Item.Opened then Close (Item); end if;
      if Writable then
         if Exists then Database.Open (Item.DB, Encode (Path)); else Database.Create (Item.DB, Encode (Path)); end if;
      else
         if not Exists then raise Dependency_Error with "Improve state database not found: " & Path; end if;
         Database.Open_Read_Only (Item.DB, Encode (Path));
      end if;
      if not Database.Last_Operation_Succeeded (Item.DB) then
         raise Dependency_Error with
           "cannot open Improve state: " & Decode (To_Wide_Wide_String (Database.Last_Result (Item.DB).Message));
      end if;
      Item.Opened := True;
      Item.Writable := Writable;
      Item.Schema_Version := 0;
      Item.Next_Ids := [others => 0];
      Item.Schemas (1) := New_Schema ("improve_records");
      if Writable then Check (Entity_Tables.Register (Item.DB, Item.Schemas (1)), "register Improve table"); end if;
      for Table in 2 .. Logical_Table_Count loop Item.Schemas (Table) := Item.Schemas (1); end loop;
      declare
         Tx : Database.Transactions.Transaction;
         Metadata : Entity;
         Status : Database.Status.Result;
      begin
         Database.Transactions.Begin_Read (Item.DB, Tx);
         Status := Entity_Tables.Find
           (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
            Physical_Key (Schema_Metadata_Table, 1), Metadata);
         Database.Transactions.Rollback (Tx);
         if Status.Code = Database.Status.Not_Found and then Writable and then not Exists then
            Database.Transactions.Begin_Write (Item.DB, Tx);
            Check
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Schema_Metadata_Table),
                  (1, 0, WW ("schema"), WW (Number (Current_Schema_Version)),
                   WW ("created_by=improve" & LF & "logical_tables=" & Logical_Table_List), True,
                   Schema_Metadata_Table)),
               "initialize schema metadata");
            Database.Transactions.Commit (Tx);
            Item.Schema_Version := Current_Schema_Version;
         elsif not Database.Status.Is_Ok (Status) then
            raise Data_Error with "Improve schema metadata is missing or unreadable";
         else
            begin
               Item.Schema_Version := Natural'Value (S (Metadata.State));
            exception
               when Constraint_Error =>
                  raise Data_Error with "unsupported Improve schema version " & S (Metadata.State);
            end;
            if Item.Schema_Version not in 1 .. Current_Schema_Version then
               raise Data_Error with "unsupported Improve schema version " & S (Metadata.State);
            elsif Item.Schema_Version < 3 and then Writable then
               Migrate_To_Version_3 (Item, Metadata);
               Item.Schema_Version := 3;
            end if;
            if Item.Schema_Version < 4 and then Writable then
               Migrate_To_Version_4 (Item, Metadata);
               Item.Schema_Version := 4;
            end if;
         end if;
      end;
   exception
      when others =>
         if Database.Is_Open (Item.DB) then Database.Close (Item.DB); end if;
         Item.Opened := False;
         raise;
   end Open;

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

function Save (Item : in out Store; Value : Improve.Model.Plan_Revision) return Save_Result is separate;

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
   begin
      if Plan_Id'Length > 10 and then Plan_Id (Plan_Id'First .. Plan_Id'First + 9) = "@revision:" then
         return Load_Revision
           (Item, Positive'Value (Plan_Id (Plan_Id'First + 10 .. Plan_Id'Last)), Limits);
      elsif Plan_Id'Length /= 11 or else Plan_Id (Plan_Id'First .. Plan_Id'First + 4) /= "PLAN-" then
         raise Argument_Error with "invalid plan identity " & Plan_Id;
      end if;
      Plan_Row := Natural'Value (Plan_Id (Plan_Id'First + 5 .. Plan_Id'Last));
      if Plan_Row = 0 then raise Constraint_Error; end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
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
      when Constraint_Error => raise Argument_Error with "invalid plan identity " & Plan_Id;
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
   begin
      if Plan_Id'Length /= 11 or else Plan_Id (Plan_Id'First .. Plan_Id'First + 4) /= "PLAN-" then
         raise Argument_Error with "invalid plan identity " & Plan_Id;
      end if;
      Plan_Row := Natural'Value (Plan_Id (Plan_Id'First + 5 .. Plan_Id'Last));
      if Plan_Row = 0 then raise Constraint_Error; end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor :=
        Scan_Children (Item, Tx, Revisions_Table, Positive (Plan_Row));
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
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
      when Constraint_Error => raise Argument_Error with "invalid plan identity " & Plan_Id;
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load;

   function Load_Task
     (Item     : in out Store;
      Task_Id  : String;
      Revision : Natural := 0;
      Limits   : Read_Limits := Default_Read_Limits) return Improve.Model.Plan_Revision is
      Tx               : Database.Transactions.Transaction;
      Revision_Id      : Natural := 0;

      procedure Consider (Candidate : Positive) is
         Row    : Entity;
         Status : Database.Status.Result;
      begin
         if Revision = 0 then
            Revision_Id := Natural'Max (Revision_Id, Candidate);
            return;
         end if;
         Status := Entity_Tables.Find
           (Tx, Item.DB, Item.Schemas (Revisions_Table),
            Physical_Key (Revisions_Table, Candidate), Row);
         Check (Status, "read task plan revision");
         if Positive'Value (Field (S (Row.Payload), "revision")) = Revision then
            Revision_Id := Candidate;
         end if;
      end Consider;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      if Item.Schema_Version >= 4 then
         declare Identities : Entity_Tables.Cursor :=
           Scan_Kind (Item, Tx, Task_Identities_Table, Task_Id);
         begin
            while Entity_Tables.Has_Element (Identities) loop
               Consider (Positive (Entity_Tables.Element (Identities).Parent_Id));
               Advance_Kind (Item, Tx, Task_Identities_Table, Task_Id, Identities);
            end loop;
         end;
      else
         declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
            while Entity_Tables.Has_Element (Tasks) loop
               declare
                  Task_Row : constant Entity := Entity_Tables.Element (Tasks);
                  Payload  : constant String := S (Task_Row.Payload);
               begin
                  if Field_Or (Payload, "draft_id", "") = Task_Id then
                     Consider (Positive (Task_Row.Parent_Id));
                  end if;
               end;
               Advance (Item, Tx, Tasks_Table, Tasks);
            end loop;
         end;
      end if;
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then
         raise Argument_Error with
           "unknown Improve task " & Task_Id &
           (if Revision = 0 then "" else " in revision " & Number (Revision));
      end if;
      return Load_Revision (Item, Positive (Revision_Id), Limits);
   exception
      when Constraint_Error =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise Data_Error with "stored task revision is malformed";
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load_Task;

   function Latest_Revision_Id
     (Item     : in out Store;
      Tx       : in out Database.Transactions.Transaction;
      Plan_Row : Positive) return Natural is
      Result    : Natural := 0;
      Revisions : Entity_Tables.Cursor := Scan_Children (Item, Tx, Revisions_Table, Plan_Row);
   begin
      while Entity_Tables.Has_Element (Revisions) loop
         Result := Natural'Max (Result, Entity_Tables.Element (Revisions).Id);
         Advance_Children (Item, Tx, Revisions_Table, Plan_Row, Revisions);
      end loop;
      return Result;
   end Latest_Revision_Id;

   function Summary_Of
     (Item        : in out Store;
      Tx          : in out Database.Transactions.Transaction;
      Revision_Id : Positive) return Plan_Summary is
      Revision : Entity;
      Status   : Database.Status.Result;
      Tasks    : Natural := 0;
   begin
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Revisions_Table),
         Physical_Key (Revisions_Table, Revision_Id), Revision);
      Check (Status, "read plan revision summary");
      declare
         Payload : constant String := S (Revision.Payload);
      begin
         if Has_Field (Payload, "task_count") then
            Tasks := Natural'Value (Field (Payload, "task_count"));
         else
            declare Cursor : Entity_Tables.Cursor :=
              Scan_Children (Item, Tx, Tasks_Table, Revision_Id);
            begin
               while Entity_Tables.Has_Element (Cursor) loop
                  if Tasks >= Default_Read_Limits.Maximum_Tasks then
                     raise Data_Error with "plan summary exceeds configured task read limit";
                  end if;
                  Tasks := Tasks + 1;
                  Advance_Children (Item, Tx, Tasks_Table, Revision_Id, Cursor);
               end loop;
            end;
         end if;
         return
           (Plan_Id     => To_Unbounded_String (Id_Image ("PLAN-", Positive (Revision.Parent_Id))),
            Revision    => Positive'Value (Field (Payload, "revision")),
            Project_Id  => Positive'Value (Field (Payload, "project_id")),
            Project     => To_Unbounded_String (Field (Payload, "project")),
            Run_Id      => Positive'Value (Field (Payload, "run_id")),
            Task_Count  => Tasks,
            Fingerprint => To_Unbounded_String (S (Revision.Kind)));
      end;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored plan summary is malformed";
   end Summary_Of;

   function List_All
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum) return Summary_Vectors.Vector is
      Result : Summary_Vectors.Vector;
      Tx : Database.Transactions.Transaction;
      Plans : Entity_Tables.Cursor;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Plans := Scan (Item, Tx, Plans_Table);
      while Entity_Tables.Has_Element (Plans) loop
         declare
            Row    : constant Entity := Entity_Tables.Element (Plans);
            Latest : constant Natural := Latest_Revision_Id (Item, Tx, Row.Id);
         begin
            if Latest > 0 then
               if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                  raise Data_Error with "plan query exceeds configured item limit";
               end if;
               Result.Append (Summary_Of (Item, Tx, Positive (Latest)));
            end if;
         end;
         Advance (Item, Tx, Plans_Table, Plans);
      end loop;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end List_All;

   function List
     (Item    : in out Store;
      Project : Improve.Model.Project_Reference;
      Maximum : Positive := Default_Query_Maximum) return Summary_Vectors.Vector is
      Result : Summary_Vectors.Vector;
      Tx : Database.Transactions.Transaction;
      Plans : Entity_Tables.Cursor;
      Current_Key : constant String := Project_Key (Project);
      Legacy_Key  : constant String := Legacy_Project_Key (Project);

      procedure Read (Key : String) is
      begin
         Plans := Scan_Kind (Item, Tx, Plans_Table, Key);
         while Entity_Tables.Has_Element (Plans) loop
            declare
               Row    : constant Entity := Entity_Tables.Element (Plans);
               Latest : constant Natural := Latest_Revision_Id (Item, Tx, Row.Id);
            begin
               if Latest > 0 then
                  if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                     raise Data_Error with "plan query exceeds configured item limit";
                  end if;
                  declare
                     Revision : Entity;
                     Status   : constant Database.Status.Result :=
                       Entity_Tables.Find
                         (Tx, Item.DB, Item.Schemas (Revisions_Table),
                          Physical_Key (Revisions_Table, Positive (Latest)), Revision);
                  begin
                     Check (Status, "read plan identity summary");
                     declare
                        Payload : constant String := S (Revision.Payload);
                     begin
                        if Positive'Value (Field (Payload, "project_id")) = Project.Id and then
                          Field (Payload, "project_path") = To_String (Project.Path) and then
                          Field_Or (Payload, "quality_database", "") = To_String (Project.Database_Id)
                        then
                           Result.Append (Summary_Of (Item, Tx, Positive (Latest)));
                        end if;
                     end;
                  end;
               end if;
            end;
            Advance_Kind (Item, Tx, Plans_Table, Key, Plans);
         end loop;
      end Read;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Read (Current_Key);
      if Legacy_Key /= Current_Key then Read (Legacy_Key); end if;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end List;

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector) is
      Tx     : Database.Transactions.Transaction;
      Row_Id : Positive;
      Stored : String_Value_Maps.Map;
      Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

      function Mapping_Key (Task_Id, Contract : String) return String is
        (Task_Id & Character'Val (0) & Contract);
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication recording";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Plan_Row); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
            begin
               Stored.Include
                 (Mapping_Key (S (Row.Kind), Field_Or (Payload, "contract", "")),
                  To_Unbounded_String
                    (Field (Payload, "harness_id") & Character'Val (0) & Field (Payload, "origin")));
            end;
            Advance_Children (Item, Tx, Publications_Table, Plan_Row, Cursor);
         end loop;
      end;
      for Value of Values loop
         declare
            Key      : constant String := Mapping_Key
              (To_String (Value.Improve_Task_Id), To_String (Value.Contract));
            Expected : constant String :=
              To_String (Value.Harness_Task_Id) & Character'Val (0) & To_String (Value.Origin);
            Existing : constant Boolean := Stored.Contains (Key);
         begin
            if Existing and then To_String (Stored.Element (Key)) /= Expected then
               raise Data_Error with "published task identity is already mapped to unrelated work";
            end if;
            if not Existing then
               Row_Id := Next_Id (Item, Tx, Publications_Table);
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Publications_Table),
                     (Row_Id, Plan_Row, WW (To_String (Value.Improve_Task_Id)), WW (To_String (Value.State)),
                      WW (Pair ("plan_id", Plan_Id) & LF &
                          Pair ("harness_id", To_String (Value.Harness_Task_Id)) & LF &
                          Pair ("origin", To_String (Value.Origin)) & LF &
                          Pair ("contract", To_String (Value.Contract)) & LF &
                          Pair ("plan_revision", Number (Value.Plan_Revision))), True, Publications_Table)),
                  "record publication mapping");
               Stored.Insert (Key, To_Unbounded_String (Expected));
            end if;
         end;
      end loop;
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Record_Publications;

   function Publications
     (Item       : in out Store;
      Plan_Id    : String := "";
      Maximum    : Positive := Default_Query_Maximum) return Publication_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Result : Publication_Vectors.Vector;

      procedure Append_Row (Row : Entity) is
         Payload : constant String := S (Row.Payload);
      begin
         if Result.Length >= Ada.Containers.Count_Type (Maximum) then
            raise Data_Error with "publication query exceeds configured item limit";
         end if;
         Result.Append
           (Publication_Record'
              (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
               Harness_Task_Id => To_Unbounded_String (Field (Payload, "harness_id")),
               Origin          => To_Unbounded_String (Field (Payload, "origin")),
               Contract        => To_Unbounded_String (Field_Or (Payload, "contract", "")),
               State           => To_Unbounded_String (S (Row.State)),
               Plan_Revision   => Positive'Value (Field_Or (Payload, "plan_revision", "1"))));
      end Append_Row;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      if Plan_Id = "" then
         declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
            while Entity_Tables.Has_Element (Cursor) loop
               Append_Row (Entity_Tables.Element (Cursor));
               Advance (Item, Tx, Publications_Table, Cursor);
            end loop;
         end;
      else
         declare
            Parent : constant Positive := Plan_Row_Id (Plan_Id);
            Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Parent);
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               Append_Row (Entity_Tables.Element (Cursor));
               Advance_Children (Item, Tx, Publications_Table, Parent, Cursor);
            end loop;
         end;
         if Item.Schema_Version < 3 then
            declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table); begin
               while Entity_Tables.Has_Element (Cursor) loop
                  declare
                     Row : constant Entity := Entity_Tables.Element (Cursor);
                     Payload : constant String := S (Row.Payload);
                  begin
                     if Row.Parent_Id = 0 and then Field (Payload, "plan_id") = Plan_Id then
                        Append_Row (Row);
                     end if;
                  end;
                  Advance (Item, Tx, Publications_Table, Cursor);
               end loop;
            end;
         end if;
      end if;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Publications;

   procedure Update_Publication_States
     (Item   : in out Store;
      Plan_Id : String;
      Values : Publication_Vectors.Vector) is
      Tx : Database.Transactions.Transaction;
      Rows : String_Id_Maps.Map;
      Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

      function Mapping_Key (Task_Id, Contract : String) return String is
        (Task_Id & Character'Val (0) & Contract);
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication reconciliation";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Publications_Table, Plan_Row); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
            begin
               Rows.Include
                 (Mapping_Key (S (Row.Kind), Field_Or (Payload, "contract", "")), Row.Id);
            end;
            Advance_Children (Item, Tx, Publications_Table, Plan_Row, Cursor);
         end loop;
      end;
      for Value of Values loop
         declare
            Key : constant String := Mapping_Key
              (To_String (Value.Improve_Task_Id), To_String (Value.Contract));
            Row : Entity;
            Status : Database.Status.Result;
         begin
            if not Rows.Contains (Key) then
               raise Data_Error with "publication reconciliation references an unknown Improve task";
            end if;
            Status := Entity_Tables.Find
              (Tx, Item.DB, Item.Schemas (Publications_Table),
               Physical_Key (Publications_Table, Rows.Element (Key)), Row);
            Check (Status, "read publication mapping for reconciliation");
            declare Payload : constant String := S (Row.Payload); begin
               if Field (Payload, "harness_id") /= To_String (Value.Harness_Task_Id) or else
                 Field (Payload, "origin") /= To_String (Value.Origin)
               then
                  raise Data_Error with "publication reconciliation identity does not match stored mapping";
               end if;
            end;
            Row.State := WW (To_String (Value.State));
            Check
              (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Publications_Table), Row),
               "update reconciled publication state");
         end;
      end loop;
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Update_Publication_States;

   procedure Record_Verification
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Verification_Vectors.Vector) is
      Tx     : Database.Transactions.Transaction;
      Row_Id : Positive;
      Stored : String_Value_Maps.Map;
      Plan_Row : constant Positive := Plan_Row_Id (Plan_Id);

      function Scope_Image (Value : Verification_Scope) return String is
        (case Value is
            when Task_Evaluation => "task",
            when Plan_Evaluation => "plan",
            when Project_Evaluation => "project");

      function Record_Key (Value : Verification_Record) return String is
        (case Value.Scope is
            when Task_Evaluation => To_String (Value.Task_Id),
            when Plan_Evaluation => "@plan",
            when Project_Evaluation => "@project");

      function Identity_Key
        (Key, Plan, Assessment, Revision, Contract : String) return String is
        (Key & Character'Val (0) & Plan & Character'Val (0) & Assessment & Character'Val (0) &
         Revision & Character'Val (0) & Contract);

      function Stored_Value (State, Scope, Comparable, Explanation : String) return String is
        (State & Character'Val (0) & Scope & Character'Val (0) & Comparable & Character'Val (0) & Explanation);
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for verification recording";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Plan_Row); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
            begin
               Stored.Include
                 (Identity_Key
                    (S (Row.Kind), Field (Payload, "plan_id"), Field (Payload, "assessment_id"),
                     Field_Or (Payload, "plan_revision", "1"), Field_Or (Payload, "contract", "")),
                  To_Unbounded_String
                    (Stored_Value
                       (S (Row.State), Field_Or (Payload, "scope", "task"),
                        Field (Payload, "comparable"), Field (Payload, "explanation"))));
            end;
            Advance_Children (Item, Tx, Verifications_Table, Plan_Row, Cursor);
         end loop;
      end;
      for Value of Values loop
         declare
            Key      : constant String := Record_Key (Value);
            Identity : constant String := Identity_Key
              (Key, Plan_Id, Number (Value.Assessment_Id), Number (Value.Plan_Revision),
               To_String (Value.Contract_Fingerprint));
            Expected : constant String := Stored_Value
              (Improve.Model.Image (Value.Outcome), Scope_Image (Value.Scope), Boolean_Image (Value.Comparable),
               To_String (Value.Explanation));
            Existing : constant Boolean := Stored.Contains (Identity);
         begin
            if Value.Scope = Task_Evaluation and then Length (Value.Task_Id) = 0 then
               raise Data_Error with "task verification has no task identity";
            elsif Value.Scope /= Task_Evaluation and then Length (Value.Task_Id) > 0 then
               raise Data_Error with "aggregate verification must not name a task";
            end if;
            if Existing and then To_String (Stored.Element (Identity)) /= Expected then
               raise Data_Error with "verification evidence conflicts for task and assessment";
            end if;
            if not Existing then
               Row_Id := Next_Id (Item, Tx, Verifications_Table);
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Verifications_Table),
                     (Row_Id, Plan_Row, WW (Key), WW (Improve.Model.Image (Value.Outcome)),
                      WW (Pair ("plan_id", Plan_Id) & LF &
                          Pair ("assessment_id", Number (Value.Assessment_Id)) & LF &
                          Pair ("plan_revision", Number (Value.Plan_Revision)) & LF &
                          Pair ("contract", To_String (Value.Contract_Fingerprint)) & LF &
                          Pair ("scope", Scope_Image (Value.Scope)) & LF &
                          Pair ("task_id", To_String (Value.Task_Id)) & LF &
                          Pair ("comparable", Boolean_Image (Value.Comparable)) & LF &
                          Pair ("explanation", To_String (Value.Explanation))), True, Verifications_Table)),
                  "record verification evidence");
               Stored.Insert (Identity, To_Unbounded_String (Expected));
            end if;
         end;
      end loop;
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Record_Verification;

   function Parse_Outcome (Value : String) return Improve.Model.Quality_Outcome is
   begin
      for Outcome in Improve.Model.Quality_Outcome loop
         if Improve.Model.Image (Outcome) = Value then return Outcome; end if;
      end loop;
      raise Data_Error with "stored verification outcome is invalid: " & Value;
   end Parse_Outcome;

   function Parse_Scope (Value : String) return Verification_Scope is
   begin
      if Value = "task" then return Task_Evaluation;
      elsif Value = "plan" then return Plan_Evaluation;
      elsif Value = "project" then return Project_Evaluation;
      else raise Data_Error with "stored verification scope is invalid: " & Value;
      end if;
   end Parse_Scope;

   function Verifications
     (Item    : in out Store;
      Plan_Id : String := "";
      Task_Id : String := "";
      Maximum : Positive := Default_Query_Maximum) return Verification_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Result : Verification_Vectors.Vector;

      procedure Append_Row (Row : Entity) is
         Payload : constant String := S (Row.Payload);
         Scope   : constant Verification_Scope := Parse_Scope (Field_Or (Payload, "scope", "task"));
         Stored_Task : constant String :=
           (if Scope = Task_Evaluation then Field_Or (Payload, "task_id", S (Row.Kind)) else "");
      begin
         if Task_Id = "" or else (Scope = Task_Evaluation and then Stored_Task = Task_Id) then
            if Result.Length >= Ada.Containers.Count_Type (Maximum) then
               raise Data_Error with "verification query exceeds configured item limit";
            end if;
            Result.Append
              (Verification_Record'
                 (Scope         => Scope,
                  Task_Id       => To_Unbounded_String (Stored_Task),
                  Plan_Revision => Positive'Value (Field_Or (Payload, "plan_revision", "1")),
                  Contract_Fingerprint => To_Unbounded_String (Field_Or (Payload, "contract", "")),
                  Assessment_Id => Positive'Value (Field (Payload, "assessment_id")),
                  Outcome       => Parse_Outcome (S (Row.State)),
                  Comparable    => Boolean'Value (Field (Payload, "comparable")),
                  Explanation   => To_Unbounded_String (Field (Payload, "explanation"))));
         end if;
      exception
         when Constraint_Error => raise Data_Error with "stored verification evidence is malformed";
      end Append_Row;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      if Plan_Id = "" then
         declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table); begin
            while Entity_Tables.Has_Element (Cursor) loop
               Append_Row (Entity_Tables.Element (Cursor));
               Advance (Item, Tx, Verifications_Table, Cursor);
            end loop;
         end;
      else
         declare
            Parent : constant Positive := Plan_Row_Id (Plan_Id);
            Cursor : Entity_Tables.Cursor := Scan_Children (Item, Tx, Verifications_Table, Parent);
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               Append_Row (Entity_Tables.Element (Cursor));
               Advance_Children (Item, Tx, Verifications_Table, Parent, Cursor);
            end loop;
         end;
         if Item.Schema_Version < 3 then
            declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table); begin
               while Entity_Tables.Has_Element (Cursor) loop
                  declare
                     Row : constant Entity := Entity_Tables.Element (Cursor);
                     Payload : constant String := S (Row.Payload);
                  begin
                     if Row.Parent_Id = 0 and then Field (Payload, "plan_id") = Plan_Id then
                        Append_Row (Row);
                     end if;
                  end;
                  Advance (Item, Tx, Verifications_Table, Cursor);
               end loop;
            end;
         end if;
      end if;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Verifications;

   procedure Approve
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Read_Limits := Default_Read_Limits) is
      Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
      Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
      Tx     : Database.Transactions.Transaction;
      Row_Id : Positive;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for plan approval";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
            begin
               if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
                 Field_Or (Payload, "fingerprint", "") = To_String (Plan.Fingerprint)
               then
                  Database.Transactions.Rollback (Tx);
                  return;
               end if;
            end;
            Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
         end loop;
      end;
      Row_Id := Next_Id (Item, Tx, Operations_Table);
      Check
        (Entity_Tables.Insert
           (Tx, Item.DB, Item.Schemas (Operations_Table),
            (Row_Id, 0, WW (Key), WW ("approved"),
             WW (Pair ("plan_id", Plan_Id) & LF &
                 Pair ("revision", Number (Revision)) & LF &
                 Pair ("fingerprint", To_String (Plan.Fingerprint))), True, Operations_Table)),
         "record plan approval");
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Approve;

   function Is_Approved
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive;
      Limits   : Read_Limits := Default_Read_Limits) return Boolean is
      Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision, Limits);
      Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
      Tx     : Database.Transactions.Transaction;
      Result : Boolean := False;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row     : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
            begin
               if S (Row.Kind) = Key and then S (Row.State) = "approved" and then
                 Field_Or (Payload, "fingerprint", "") = To_String (Plan.Fingerprint)
               then
                  Result := True;
                  exit;
               end if;
            end;
            Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Is_Approved;

   function Begin_Publication
     (Item     : in out Store;
      Plan     : Improve.Model.Plan_Revision;
      Task_Ids : Improve.Model.UString_Vectors.Vector;
      Limits   : Read_Limits := Default_Read_Limits) return Positive is
      Stored  : constant Improve.Model.Plan_Revision :=
        Load (Item, To_String (Plan.Plan_Id), Plan.Revision, Limits);
      Tx      : Database.Transactions.Transaction;
      Packed  : constant String := Pack (Task_Ids);
      Key     : constant String :=
        "publish:" & To_String (Plan.Plan_Id) & ":" & Number (Plan.Revision) & ":" & Stable_Digest (Packed);
      Row_Id  : Positive;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication journaling";
      elsif Task_Ids.Is_Empty then
         raise Argument_Error with "publication operation has no tasks";
      elsif Stored.Fingerprint /= Plan.Fingerprint then
         raise Data_Error with "publication plan revision fingerprint does not match durable state";
      end if;
      for Task_Id of Task_Ids loop
         declare Found : Boolean := False; begin
            for Spec of Stored.Tasks loop
               if Spec.Id = Task_Id then Found := True; exit; end if;
            end loop;
            if not Found then raise Data_Error with "publication operation references an unknown task"; end if;
         end;
      end loop;
      for Left in 1 .. Natural (Task_Ids.Length) loop
         for Right in Left + 1 .. Natural (Task_Ids.Length) loop
            if Task_Ids (Left) = Task_Ids (Right) then
               raise Data_Error with "publication operation contains a duplicate task";
            end if;
         end loop;
      end loop;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan_Kind (Item, Tx, Operations_Table, Key); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if S (Row.Kind) = Key and then S (Row.State) = "started" then
                  Database.Transactions.Rollback (Tx);
                  return Row.Id;
               end if;
            end;
            Advance_Kind (Item, Tx, Operations_Table, Key, Cursor);
         end loop;
      end;
      Row_Id := Next_Id (Item, Tx, Operations_Table);
      Check
        (Entity_Tables.Insert
           (Tx, Item.DB, Item.Schemas (Operations_Table),
            (Row_Id, 0, WW (Key), WW ("started"),
             WW (Pair ("plan_id", To_String (Plan.Plan_Id)) & LF &
                 Pair ("revision", Number (Plan.Revision)) & LF &
                 Pair ("fingerprint", To_String (Plan.Fingerprint)) & LF &
                 Pair ("task_ids", Packed)), True, Operations_Table)),
         "journal publication start");
      Database.Transactions.Commit (Tx);
      return Row_Id;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Begin_Publication;

   procedure Complete_Publication (Item : in out Store; Operation_Id : Positive) is
      Tx      : Database.Transactions.Transaction;
      Started : Entity;
      Found   : Boolean := False;
      Row_Id  : Positive;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication completion";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare
         Status : constant Database.Status.Result :=
           Entity_Tables.Find
             (Tx, Item.DB, Item.Schemas (Operations_Table),
              Physical_Key (Operations_Table, Operation_Id), Started);
      begin
         if Database.Status.Is_Ok (Status) and then S (Started.State) = "started" then
            Found := True;
         elsif Status.Code /= Database.Status.Not_Found then
            Check (Status, "read publication operation");
         end if;
      end;
      if not Found then raise Data_Error with "unknown publication operation"; end if;
      declare Ends : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Operation_Id); begin
         while Entity_Tables.Has_Element (Ends) loop
            if S (Entity_Tables.Element (Ends).State) = "completed" then
               Database.Transactions.Rollback (Tx);
               return;
            end if;
            Advance_Children (Item, Tx, Operations_Table, Operation_Id, Ends);
         end loop;
      end;
      Row_Id := Next_Id (Item, Tx, Operations_Table);
      Check
        (Entity_Tables.Insert
           (Tx, Item.DB, Item.Schemas (Operations_Table),
            (Row_Id, Operation_Id, Started.Kind, WW ("completed"), Started.Payload, True, Operations_Table)),
         "journal publication completion");
      Database.Transactions.Commit (Tx);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Complete_Publication;

   function Pending_Publications
     (Item    : in out Store;
      Maximum : Positive := Default_Query_Maximum;
      Limits  : Read_Limits := Default_Read_Limits) return Operation_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Result : Operation_Vectors.Vector;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Starts : Entity_Tables.Cursor := Scan_State (Item, Tx, Operations_Table, "started"); begin
         while Entity_Tables.Has_Element (Starts) loop
            declare
               Row       : constant Entity := Entity_Tables.Element (Starts);
               Completed : Boolean := False;
               Ends      : Entity_Tables.Cursor := Scan_Children (Item, Tx, Operations_Table, Row.Id);
            begin
               while Entity_Tables.Has_Element (Ends) loop
                  if S (Entity_Tables.Element (Ends).State) = "completed" then
                     Completed := True;
                     exit;
                  end if;
                  Advance_Children (Item, Tx, Operations_Table, Row.Id, Ends);
               end loop;
               if not Completed then
                  if Result.Length >= Ada.Containers.Count_Type (Maximum) then
                     raise Data_Error with "pending publication query exceeds configured item limit";
                  end if;
                  declare Payload : constant String := S (Row.Payload); begin
                     Require_Payload_Limit (Payload, Limits, "publication operation payload");
                     Result.Append
                       (Operation_Record'
                          (Id       => Row.Id,
                           Key      => To_Unbounded_String (S (Row.Kind)),
                           Plan_Id  => To_Unbounded_String (Field (Payload, "plan_id")),
                           Revision => Positive'Value (Field_Or (Payload, "revision", "1")),
                           Fingerprint => To_Unbounded_String (Field_Or (Payload, "fingerprint", "")),
                           Task_Ids =>
                             Unpack
                               (Field (Payload, "task_ids"), Limits.Maximum_Tasks,
                                Limits.Maximum_Text_Bytes)));
                  end;
               end if;
            end;
            Advance_State (Item, Tx, Operations_Table, "started", Starts);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Pending_Publications;
end Improve.Storage;
