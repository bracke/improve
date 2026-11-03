with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Types;
with Database.Predicates;
with Database.Rows;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;

package body Improve.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use type Database.Status_Code;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

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

   Table_Names : constant array (Positive range 1 .. Logical_Table_Count) of access constant Wide_Wide_String :=
     [new Wide_Wide_String'("schema_metadata"), new Wide_Wide_String'("projects"),
      new Wide_Wide_String'("assessment_baselines"), new Wide_Wide_String'("finding_references"),
      new Wide_Wide_String'("plans"), new Wide_Wide_String'("plan_revisions"),
      new Wide_Wide_String'("remediation_tasks"), new Wide_Wide_String'("task_finding_links"),
      new Wide_Wide_String'("task_dependencies"), new Wide_Wide_String'("publications"),
      new Wide_Wide_String'("verification_records"), new Wide_Wide_String'("operations")];

   function Decode (Text : Wide_Wide_String) return String;

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

   function Encode (Text : String) return Wide_Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text));

   function Decode (Text : Wide_Wide_String) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Text));

   function WW (Text : String) return Unbounded_Wide_Wide_String is
     (To_Unbounded_Wide_Wide_String (Encode (Text)));

   function S (Text : Unbounded_Wide_Wide_String) return String is
     (Decode (To_Wide_Wide_String (Text)));

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

   function Escape (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '\' => Append (Result, "\\");
            when LF => Append (Result, "\n");
            when CR => Append (Result, "\r");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   function Unescape (Text : String) return String is
      Result : Unbounded_String;
      Index  : Natural := Text'First;
   begin
      while Index <= Text'Last loop
         if Text (Index) = '\' then
            if Index = Text'Last then raise Data_Error with "invalid persisted escape sequence"; end if;
            case Text (Index + 1) is
               when '\' => Append (Result, '\');
               when 'n' => Append (Result, LF);
               when 'r' => Append (Result, CR);
               when others => raise Data_Error with "invalid persisted escape sequence";
            end case;
            Index := Index + 2;
         else
            Append (Result, Text (Index));
            Index := Index + 1;
         end if;
      end loop;
      return To_String (Result);
   end Unescape;

   function Field (Payload, Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Natural := Payload'First;
   begin
      while Start <= Payload'Last loop
         declare Stop : Natural := Start; begin
            while Stop <= Payload'Last and then Payload (Stop) /= LF loop Stop := Stop + 1; end loop;
            if Stop - Start >= Prefix'Length and then Payload (Start .. Start + Prefix'Length - 1) = Prefix then
               return Unescape (Payload (Start + Prefix'Length .. Stop - 1));
            end if;
            Start := Stop + 1;
         end;
      end loop;
      raise Data_Error with "missing persisted field " & Name;
   end Field;

   function Field_Or (Payload, Name, Default : String) return String is
   begin
      return Field (Payload, Name);
   exception
      when Data_Error => return Default;
   end Field_Or;

   function Pair (Name, Value : String) return String is (Name & "=" & Escape (Value));

   function Number (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Boolean_Image (Value : Boolean) return String is (if Value then "true" else "false");

   function Pack (Values : Improve.Model.UString_Vectors.Vector) return String is
      Result : Unbounded_String;
   begin
      for Value of Values loop
         declare Text : constant String := To_String (Value); begin
            Append (Result, Number (Text'Length) & ":" & Text);
         end;
      end loop;
      return To_String (Result);
   end Pack;

   function Unpack (Text : String) return Improve.Model.UString_Vectors.Vector is
      Result : Improve.Model.UString_Vectors.Vector;
      Index  : Natural := Text'First;
   begin
      while Index <= Text'Last loop
         declare Colon : Natural := Index; begin
            while Colon <= Text'Last and then Text (Colon) /= ':' loop
               if Text (Colon) not in '0' .. '9' then raise Data_Error with "invalid persisted list"; end if;
               Colon := Colon + 1;
            end loop;
            if Colon > Text'Last or else Colon = Index then raise Data_Error with "invalid persisted list"; end if;
            declare
               Length : constant Natural := Natural'Value (Text (Index .. Colon - 1));
               First  : constant Natural := Colon + 1;
               Last   : constant Natural := Colon + Length;
            begin
               if Last > Text'Last then raise Data_Error with "truncated persisted list"; end if;
               Result.Append (To_Unbounded_String (Text (First .. Last)));
               Index := Last + 1;
            end;
         end;
      end loop;
      return Result;
   exception
      when Constraint_Error => raise Data_Error with "invalid persisted list length";
   end Unpack;

   function Timestamp (Value : Ada.Calendar.Time) return String is
     (Ada.Calendar.Formatting.Image (Value, Include_Time_Fraction => False, Time_Zone => 0));

   function Parse_Time (Text : String) return Ada.Calendar.Time is
     (Ada.Calendar.Formatting.Value (Text, Time_Zone => 0));

   function Id_Image (Prefix : String; Id : Positive) return String is
      Value_Text : constant String := Number (Id);
   begin
      return Prefix & [1 .. Integer'Max (0, 6 - Value_Text'Length) => '0'] & Value_Text;
   end Id_Image;

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

   function Next_Id
     (Item : in out Store; Tx : in out Database.Transactions.Transaction; Table : Positive) return Positive is
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Table);
      Highest : Natural := 0;
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         Highest := Natural'Max (Highest, Entity_Tables.Element (Cursor).Id);
         Advance (Item, Tx, Table, Cursor);
      end loop;
      return Highest + 1;
   end Next_Id;

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
         elsif not Database.Status.Is_Ok (Status) then
            raise Data_Error with "Improve schema metadata is missing or unreadable";
         elsif S (Metadata.State) /= Number (Current_Schema_Version) then
            raise Data_Error with "unsupported Improve schema version " & S (Metadata.State);
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
   end Close;

   function Finding_Payload (Value : Improve.Model.Finding_Reference) return String is
     (Pair ("indicator", Ada_Quality.Types.Image (Value.Indicator)) & LF & Pair ("rule", To_String (Value.Rule)) & LF &
      Pair ("severity", Ada_Quality.Types.Severity'Image (Value.Level)) & LF &
      Pair ("path", To_String (Value.Relative_Path)) & LF & Pair ("line", Number (Value.Line)) & LF &
      Pair ("subject", To_String (Value.Semantic_Subject)) & LF & Pair ("message", To_String (Value.Message)) & LF &
      Pair ("evidence", To_String (Value.Evidence)) & LF &
      Pair ("indicator_level", Boolean_Image (Value.Indicator_Level)));

   function Task_Payload (Value : Improve.Model.Task_Specification) return String is
     (Pair ("draft_id", To_String (Value.Id)) & LF & Pair ("title", To_String (Value.Title)) & LF &
      Pair ("priority", Improve.Model.Image (Value.Task_Priority)) & LF & Pair ("goal", To_String (Value.Goal)) & LF &
      Pair ("problem", To_String (Value.Problem)) & LF & Pair ("evidence", To_String (Value.Evidence)) & LF &
      Pair ("files", Pack (Value.Relevant_Files)) & LF & Pair ("scope", To_String (Value.Scope)) & LF &
      Pair ("out_of_scope", To_String (Value.Out_Of_Scope)) & LF &
      Pair ("requirements", To_String (Value.Requirements)) & LF &
      Pair ("acceptance", To_String (Value.Acceptance)) & LF &
      Pair ("verification", To_String (Value.Verification)) & LF &
      Pair ("dependencies", Pack (Value.Dependencies)) & LF & Pair ("finding_keys", Pack (Value.Finding_Keys)) & LF &
      Pair ("confidence", Number (Value.Confidence)) & LF & Pair ("review", Boolean_Image (Value.Requires_Review)));

   function Revision_Payload (Value : Improve.Model.Plan_Revision; Baseline_Id, Revision : Positive) return String is
     (Pair ("revision", Number (Revision)) & LF & Pair ("baseline_id", Number (Baseline_Id)) & LF &
      Pair ("project_id", Number (Value.Project.Id)) & LF & Pair ("project", To_String (Value.Project.Name)) & LF &
      Pair ("project_path", To_String (Value.Project.Path)) & LF &
      Pair ("run_id", Number (Value.Baseline.Run_Id)) & LF &
      Pair ("source", To_String (Value.Baseline.Source_Id)) & LF &
      Pair ("working_source", To_String (Value.Working_Source_Id)) & LF &
      Pair ("policy", To_String (Value.Baseline.Policy_Id)) & LF &
      Pair ("toolchain", To_String (Value.Baseline.Toolchain_Id)) & LF &
      Pair ("snapshot", To_String (Value.Baseline.Snapshot_Id)) & LF &
      Pair ("planner", To_String (Value.Planner_Id)) & LF & Pair ("created_at", Timestamp (Value.Created_At)));

   function Find_Revision
     (Item : in out Store; Tx : in out Database.Transactions.Transaction; Fingerprint : String) return Natural is
      Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table);
   begin
      while Entity_Tables.Has_Element (Cursor) loop
         if S (Entity_Tables.Element (Cursor).Kind) = Fingerprint then
            return Entity_Tables.Element (Cursor).Id;
         end if;
         Advance (Item, Tx, Revisions_Table, Cursor);
      end loop;
      return 0;
   end Find_Revision;

   function Save (Item : in out Store; Value : Improve.Model.Plan_Revision) return Save_Result is
      Tx : Database.Transactions.Transaction;
      Stored : Improve.Model.Plan_Revision := Value;
      Existing_Revision : Natural;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for writing";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Existing_Revision := Find_Revision (Item, Tx, To_String (Value.Fingerprint));
      if Existing_Revision > 0 then
         Database.Transactions.Rollback (Tx);
         return (Plan => Load (Item, "@revision:" & Number (Existing_Revision)), Existing => True);
      end if;
      Stored.Created_At := Ada.Calendar.Clock;
      declare
         Project_Row  : constant Positive := Next_Id (Item, Tx, Projects_Table);
         Baseline_Row : constant Positive := Next_Id (Item, Tx, Baselines_Table);
         Plan_Row     : Positive := Next_Id (Item, Tx, Plans_Table);
         Revision_Row : constant Positive := Next_Id (Item, Tx, Revisions_Table);
         Revision_No  : Positive := 1;
         Previous_Revision : Natural := 0;
         Cursor       : Entity_Tables.Cursor := Scan (Item, Tx, Plans_Table);
      begin
         while Entity_Tables.Has_Element (Cursor) and then
           S (Entity_Tables.Element (Cursor).Kind) /= Number (Stored.Project.Id)
         loop
            Advance (Item, Tx, Plans_Table, Cursor);
         end loop;
         if Entity_Tables.Has_Element (Cursor) then
            Plan_Row := Entity_Tables.Element (Cursor).Id;
            declare Revisions : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table);
            begin
               while Entity_Tables.Has_Element (Revisions) loop
                  if Entity_Tables.Element (Revisions).Parent_Id = Plan_Row then
                     Previous_Revision := Natural'Max
                       (Previous_Revision, Entity_Tables.Element (Revisions).Id);
                     Revision_No := Positive'Max
                       (Revision_No,
                        Positive'Value
                          (Field (S (Entity_Tables.Element (Revisions).Payload), "revision")) + 1);
                  end if;
                  Advance (Item, Tx, Revisions_Table, Revisions);
               end loop;
            end;
         else
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Projects_Table),
                   (Project_Row, 0, WW (Number (Stored.Project.Id)), WW ("active"), WW
                     (Pair ("name", To_String (Stored.Project.Name)) & LF &
                      Pair ("path", To_String (Stored.Project.Path))),
                    True, Projects_Table)), "store project");
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Plans_Table),
                   (Plan_Row, Stored.Project.Id, WW (Number (Stored.Project.Id)), WW ("active"), WW (""), True,
                    Plans_Table)),
                   "store plan");
         end if;
         Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Baselines_Table),
                (Baseline_Row, Stored.Project.Id, WW (Number (Stored.Baseline.Run_Id)), WW ("completed"),
                 WW (Pair ("source", To_String (Stored.Baseline.Source_Id)) & LF &
                     Pair ("policy", To_String (Stored.Baseline.Policy_Id)) & LF &
                     Pair ("toolchain", To_String (Stored.Baseline.Toolchain_Id)) & LF &
                     Pair ("snapshot", To_String (Stored.Baseline.Snapshot_Id))), True, Baselines_Table)),
                "store baseline");
         Stored.Plan_Id := To_Unbounded_String (Id_Image ("PLAN-", Plan_Row));
         Stored.Revision := Revision_No;
         Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Revisions_Table),
                (Revision_Row, Plan_Row, WW (To_String (Stored.Fingerprint)), WW (To_String (Stored.Review_Status)),
                 WW (Revision_Payload (Stored, Baseline_Row, Revision_No)), True, Revisions_Table)),
                "store plan revision");
         declare
            Finding_Row : Positive := Next_Id (Item, Tx, Findings_Table);
         begin
            for Finding of Stored.Findings loop
               Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Findings_Table),
                      (Finding_Row, Revision_Row, WW (To_String (Finding.Fingerprint)),
                       WW (Improve.Model.Image (Finding.Kind)), WW (Finding_Payload (Finding)), True, Findings_Table)),
                      "store finding");
               Finding_Row := Finding_Row + 1;
            end loop;
         end;
         declare
            First_Task_Row : constant Positive := Next_Id (Item, Tx, Tasks_Table);
            Link_Row : Positive := Next_Id (Item, Tx, Task_Findings_Table);
            Dependency_Row : Positive := Next_Id (Item, Tx, Task_Dependencies_Table);
            Original_Ids : Improve.Model.UString_Vectors.Vector;
            Assigned_Ids : Improve.Model.UString_Vectors.Vector;

            function Previous_Task_Id
              (Spec : Improve.Model.Task_Specification) return Ada.Strings.Unbounded.Unbounded_String is
               Tasks : Entity_Tables.Cursor;
            begin
               if Previous_Revision = 0 then return Null_Unbounded_String; end if;
               Tasks := Scan (Item, Tx, Tasks_Table);
               while Entity_Tables.Has_Element (Tasks) loop
                  declare
                     Row     : constant Entity := Entity_Tables.Element (Tasks);
                     Payload : constant String := S (Row.Payload);
                  begin
                     if Row.Parent_Id = Previous_Revision and then S (Row.Kind) = To_String (Spec.Category) and then
                       Field (Payload, "title") = To_String (Spec.Title) and then
                       Field (Payload, "acceptance") = To_String (Spec.Acceptance) and then
                       Field (Payload, "finding_keys") = Pack (Spec.Finding_Keys)
                     then
                        return To_Unbounded_String (Field (Payload, "draft_id"));
                     end if;
                  end;
                  Advance (Item, Tx, Tasks_Table, Tasks);
               end loop;
               return Null_Unbounded_String;
            end Previous_Task_Id;
         begin
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               Original_Ids.Append (Stored.Tasks (Index).Id);
               declare
                  Prior : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Previous_Task_Id (Stored.Tasks (Index));
                  Identity : constant Ada.Strings.Unbounded.Unbounded_String :=
                    (if Length (Prior) > 0 and then not Assigned_Ids.Contains (Prior) then Prior
                     else To_Unbounded_String (Id_Image ("IMP-", First_Task_Row + Index - 1)));
               begin
                  Stored.Tasks (Index).Id := Identity;
                  Assigned_Ids.Append (Identity);
               end;
            end loop;
            for Index in 1 .. Natural (Stored.Tasks.Length) loop
               declare
                  Task_Row  : constant Positive := First_Task_Row + Index - 1;
                  Persisted : Improve.Model.Task_Specification := Stored.Tasks (Index);
                  Translated : Improve.Model.UString_Vectors.Vector;
               begin
                  for Dependency of Persisted.Dependencies loop
                     declare Found : Boolean := False; begin
                        for Target in 1 .. Natural (Original_Ids.Length) loop
                           if Original_Ids (Target) = Dependency then
                              Translated.Append (Stored.Tasks (Target).Id);
                              Found := True;
                              exit;
                           end if;
                        end loop;
                        if not Found then
                           raise Data_Error with "task dependency is absent from the persisted plan";
                        end if;
                     end;
                  end loop;
                  Persisted.Dependencies := Translated;
                  Stored.Tasks.Replace_Element (Index, Persisted);
                  Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Tasks_Table),
                         (Task_Row, Revision_Row, WW (To_String (Persisted.Category)),
                          WW (Improve.Model.Image (Persisted.Kind)), WW (Task_Payload (Persisted)), True, Tasks_Table)),
                         "store task");
                  for Key of Persisted.Finding_Keys loop
                     Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Task_Findings_Table),
                            (Link_Row, Task_Row, WW (To_String (Key)), WW ("linked"), WW (""), True,
                             Task_Findings_Table)),
                            "store task finding link");
                     Link_Row := Link_Row + 1;
                  end loop;
                  for Dependency of Persisted.Dependencies loop
                     Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Task_Dependencies_Table),
                            (Dependency_Row, Task_Row, WW (To_String (Dependency)), WW ("required"), WW (""), True,
                             Task_Dependencies_Table)),
                            "store task dependency");
                     Dependency_Row := Dependency_Row + 1;
                  end loop;
               end;
            end loop;
         end;
         declare Operation_Row : constant Positive := Next_Id (Item, Tx, Operations_Table); begin
            Check (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Operations_Table),
                   (Operation_Row, Revision_Row, WW ("plan:" & To_String (Stored.Fingerprint)), WW ("committed"),
                    WW (Pair ("plan_id", To_String (Stored.Plan_Id))), True, Operations_Table)),
                   "journal plan operation");
         end;
      end;
      Database.Transactions.Commit (Tx);
      return (Plan => Stored, Existing => False);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Save;

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

   function Load_Revision
     (Item : in out Store; Revision_Id : Positive) return Improve.Model.Plan_Revision is
      Tx : Database.Transactions.Transaction;
      Revision : Entity;
      Result : Improve.Model.Plan_Revision;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare
         Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table);
      begin
         while Entity_Tables.Has_Element (Cursor) and then Entity_Tables.Element (Cursor).Id /= Revision_Id loop
            Advance (Item, Tx, Revisions_Table, Cursor);
         end loop;
         if not Entity_Tables.Has_Element (Cursor) then raise Argument_Error with "unknown plan revision"; end if;
         Revision := Entity_Tables.Element (Cursor);
      end;
      declare Payload : constant String := S (Revision.Payload); begin
         Result.Plan_Id := To_Unbounded_String (Id_Image ("PLAN-", Positive (Revision.Parent_Id)));
         Result.Revision := Positive'Value (Field (Payload, "revision"));
         Result.Project :=
           (Positive'Value (Field (Payload, "project_id")), To_Unbounded_String (Field (Payload, "project")),
            To_Unbounded_String (Field (Payload, "project_path")));
         Result.Baseline :=
           (Result.Project.Id, Positive'Value (Field (Payload, "run_id")),
            To_Unbounded_String (Field (Payload, "source")), To_Unbounded_String (Field (Payload, "policy")),
            To_Unbounded_String (Field (Payload, "toolchain")), To_Unbounded_String (Field (Payload, "snapshot")));
         Result.Working_Source_Id :=
           To_Unbounded_String (Field_Or (Payload, "working_source", Field (Payload, "source")));
         Result.Planner_Id := To_Unbounded_String (Field (Payload, "planner"));
         Result.Created_At := Parse_Time (Field (Payload, "created_at"));
         Result.Fingerprint := To_Unbounded_String (S (Revision.Kind));
         Result.Review_Status := To_Unbounded_String (S (Revision.State));
      end;
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Findings_Table);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
               Finding : Improve.Model.Finding_Reference;
            begin
               if Row.Parent_Id = Revision_Id then
                  Finding.Project_Id := Result.Project.Id;
                  Finding.Run_Id := Result.Baseline.Run_Id;
                  Finding.Indicator := Indicator_Value (Field (Payload, "indicator"));
                  Finding.Rule := To_Unbounded_String (Field (Payload, "rule"));
                  Finding.Level := Ada_Quality.Types.Severity'Value (Field (Payload, "severity"));
                  Finding.Relative_Path := To_Unbounded_String (Field (Payload, "path"));
                  Finding.Line := Natural'Value (Field (Payload, "line"));
                  Finding.Fingerprint := To_Unbounded_String (S (Row.Kind));
                  Finding.Semantic_Subject := To_Unbounded_String (Field (Payload, "subject"));
                  Finding.Message := To_Unbounded_String (Field (Payload, "message"));
                  Finding.Evidence := To_Unbounded_String (Field (Payload, "evidence"));
                  Finding.Kind := Kind_Value (S (Row.State));
                  Finding.Indicator_Level := Boolean'Value (Field (Payload, "indicator_level"));
                  Result.Findings.Append (Finding);
               end if;
            end;
            Advance (Item, Tx, Findings_Table, Cursor);
         end loop;
      end;
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
               Payload : constant String := S (Row.Payload);
               Spec : Improve.Model.Task_Specification;
            begin
               if Row.Parent_Id = Revision_Id then
                  Spec.Id := To_Unbounded_String (Field (Payload, "draft_id"));
                  if Length (Spec.Id) = 0 then Spec.Id := To_Unbounded_String (Id_Image ("IMP-", Row.Id)); end if;
                  Spec.Title := To_Unbounded_String (Field (Payload, "title"));
                  Spec.Category := To_Unbounded_String (S (Row.Kind));
                  Spec.Task_Priority := Priority_Value (Field (Payload, "priority"));
                  Spec.Goal := To_Unbounded_String (Field (Payload, "goal"));
                  Spec.Problem := To_Unbounded_String (Field (Payload, "problem"));
                  Spec.Evidence := To_Unbounded_String (Field (Payload, "evidence"));
                  Spec.Relevant_Files := Unpack (Field (Payload, "files"));
                  Spec.Scope := To_Unbounded_String (Field (Payload, "scope"));
                  Spec.Out_Of_Scope := To_Unbounded_String (Field (Payload, "out_of_scope"));
                  Spec.Requirements := To_Unbounded_String (Field (Payload, "requirements"));
                  Spec.Acceptance := To_Unbounded_String (Field (Payload, "acceptance"));
                  Spec.Verification := To_Unbounded_String (Field (Payload, "verification"));
                  Spec.Dependencies := Unpack (Field (Payload, "dependencies"));
                  Spec.Finding_Keys := Unpack (Field (Payload, "finding_keys"));
                  Spec.Confidence := Natural'Value (Field (Payload, "confidence"));
                  Spec.Requires_Review := Boolean'Value (Field (Payload, "review"));
                  Spec.Kind := Kind_Value (S (Row.State));
                  Result.Tasks.Append (Spec);
               end if;
            end;
            Advance (Item, Tx, Tasks_Table, Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load_Revision;

   function Load (Item : in out Store; Plan_Id : String) return Improve.Model.Plan_Revision is
      Tx : Database.Transactions.Transaction;
      Revision_Id : Natural := 0;
      Plan_Row : Natural := 0;
   begin
      if Plan_Id'Length > 10 and then Plan_Id (Plan_Id'First .. Plan_Id'First + 9) = "@revision:" then
         return Load_Revision (Item, Positive'Value (Plan_Id (Plan_Id'First + 10 .. Plan_Id'Last)));
      elsif Plan_Id'Length /= 11 or else Plan_Id (Plan_Id'First .. Plan_Id'First + 4) /= "PLAN-" then
         raise Argument_Error with "invalid plan identity " & Plan_Id;
      end if;
      Plan_Row := Natural'Value (Plan_Id (Plan_Id'First + 5 .. Plan_Id'Last));
      if Plan_Row = 0 then raise Constraint_Error; end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table);
      begin
         while Entity_Tables.Has_Element (Cursor) loop
            if Entity_Tables.Element (Cursor).Parent_Id = Plan_Row then
               Revision_Id := Natural'Max (Revision_Id, Entity_Tables.Element (Cursor).Id);
            end if;
            Advance (Item, Tx, Revisions_Table, Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then raise Argument_Error with "unknown plan " & Plan_Id; end if;
      return Load_Revision (Item, Positive (Revision_Id));
   exception
      when Constraint_Error => raise Argument_Error with "invalid plan identity " & Plan_Id;
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load;

   function Load
     (Item     : in out Store;
      Plan_Id  : String;
      Revision : Positive) return Improve.Model.Plan_Revision is
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
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Parent_Id = Plan_Row and then
                 Positive'Value (Field (S (Row.Payload), "revision")) = Revision
               then
                  Revision_Id := Row.Id;
                  exit;
               end if;
            end;
            Advance (Item, Tx, Revisions_Table, Cursor);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then
         raise Argument_Error with "unknown plan revision " & Plan_Id & " r" & Number (Revision);
      end if;
      return Load_Revision (Item, Positive (Revision_Id));
   exception
      when Constraint_Error => raise Argument_Error with "invalid plan identity " & Plan_Id;
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load;

   function Load_Task
     (Item     : in out Store;
      Task_Id  : String;
      Revision : Natural := 0) return Improve.Model.Plan_Revision is
      Tx          : Database.Transactions.Transaction;
      Revision_Id : Natural := 0;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Tasks : Entity_Tables.Cursor := Scan (Item, Tx, Tasks_Table); begin
         while Entity_Tables.Has_Element (Tasks) loop
            declare
               Task_Row : constant Entity := Entity_Tables.Element (Tasks);
               Payload  : constant String := S (Task_Row.Payload);
            begin
               if Field_Or (Payload, "draft_id", "") = Task_Id then
                  if Revision = 0 then
                     Revision_Id := Natural'Max (Revision_Id, Task_Row.Parent_Id);
                  else
                     declare Revisions : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table); begin
                        while Entity_Tables.Has_Element (Revisions) loop
                           declare Row : constant Entity := Entity_Tables.Element (Revisions); begin
                              if Row.Id = Task_Row.Parent_Id and then
                                Positive'Value (Field (S (Row.Payload), "revision")) = Revision
                              then
                                 Revision_Id := Row.Id;
                                 exit;
                              end if;
                           end;
                           Advance (Item, Tx, Revisions_Table, Revisions);
                        end loop;
                     end;
                  end if;
               end if;
            end;
            Advance (Item, Tx, Tasks_Table, Tasks);
         end loop;
      end;
      Database.Transactions.Rollback (Tx);
      if Revision_Id = 0 then
         raise Argument_Error with
           "unknown Improve task " & Task_Id &
           (if Revision = 0 then "" else " in revision " & Number (Revision));
      end if;
      return Load_Revision (Item, Positive (Revision_Id));
   exception
      when Constraint_Error =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise Data_Error with "stored task revision is malformed";
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Load_Task;

   function List
     (Item : in out Store; Project_Id : Natural := 0) return Summary_Vectors.Vector is
      Result : Summary_Vectors.Vector;
      Tx : Database.Transactions.Transaction;
      Plans : Entity_Tables.Cursor;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Plans := Scan (Item, Tx, Plans_Table);
      while Entity_Tables.Has_Element (Plans) loop
         declare Row : constant Entity := Entity_Tables.Element (Plans); begin
            if Project_Id = 0 or else Row.Parent_Id = Project_Id then
               declare
                  Revisions : Entity_Tables.Cursor := Scan (Item, Tx, Revisions_Table);
                  Latest : Natural := 0;
               begin
                  while Entity_Tables.Has_Element (Revisions) loop
                     if Entity_Tables.Element (Revisions).Parent_Id = Row.Id then
                        Latest := Natural'Max (Latest, Entity_Tables.Element (Revisions).Id);
                     end if;
                     Advance (Item, Tx, Revisions_Table, Revisions);
                  end loop;
                  if Latest > 0 then
                     declare
                        Plan : constant Improve.Model.Plan_Revision := Load_Revision (Item, Positive (Latest));
                     begin
                        Result.Append
                          (Plan_Summary'
                             (Plan.Plan_Id, Plan.Revision, Plan.Project.Id, Plan.Project.Name,
                              Plan.Baseline.Run_Id, Natural (Plan.Tasks.Length), Plan.Fingerprint));
                     end;
                  end if;
               end;
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
   end List;

   procedure Record_Publications
     (Item    : in out Store;
      Plan_Id : String;
      Values  : Publication_Vectors.Vector) is
      Tx     : Database.Transactions.Transaction;
      Row_Id : Positive;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication recording";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Row_Id := Next_Id (Item, Tx, Publications_Table);
      for Value of Values loop
         declare
            Cursor   : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table);
            Existing : Boolean := False;
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
                  if S (Row.Kind) = To_String (Value.Improve_Task_Id) then
                     if Field (S (Row.Payload), "harness_id") /= To_String (Value.Harness_Task_Id) or else
                       Field (S (Row.Payload), "origin") /= To_String (Value.Origin)
                     then
                        raise Data_Error with "published task identity is already mapped to unrelated work";
                     end if;
                     Existing := True;
                     exit;
                  end if;
               end;
               Advance (Item, Tx, Publications_Table, Cursor);
            end loop;
            if not Existing then
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Publications_Table),
                     (Row_Id, 0, WW (To_String (Value.Improve_Task_Id)), WW (To_String (Value.State)),
                      WW (Pair ("plan_id", Plan_Id) & LF &
                          Pair ("harness_id", To_String (Value.Harness_Task_Id)) & LF &
                          Pair ("origin", To_String (Value.Origin)) & LF &
                          Pair ("plan_revision", Number (Value.Plan_Revision))), True, Publications_Table)),
                  "record publication mapping");
               Row_Id := Row_Id + 1;
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
     (Item : in out Store; Plan_Id : String := "") return Publication_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Result : Publication_Vectors.Vector;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Cursor := Scan (Item, Tx, Publications_Table);
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
         begin
            if Plan_Id = "" or else Field (Payload, "plan_id") = Plan_Id then
               Result.Append
                 (Publication_Record'
                    (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
                     Harness_Task_Id => To_Unbounded_String (Field (Payload, "harness_id")),
                     Origin          => To_Unbounded_String (Field (Payload, "origin")),
                     State           => To_Unbounded_String (S (Row.State)),
                     Plan_Revision   => Positive'Value (Field_Or (Payload, "plan_revision", "1"))));
            end if;
         end;
         Advance (Item, Tx, Publications_Table, Cursor);
      end loop;
      Database.Transactions.Rollback (Tx);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Publications;

   procedure Update_Publication_States
     (Item   : in out Store;
      Values : Publication_Vectors.Vector) is
      Tx : Database.Transactions.Transaction;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for publication reconciliation";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      for Value of Values loop
         declare
            Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Publications_Table);
            Found  : Boolean := False;
         begin
            while Entity_Tables.Has_Element (Cursor) loop
               declare
                  Row     : Entity := Entity_Tables.Element (Cursor);
                  Payload : constant String := S (Row.Payload);
               begin
                  if S (Row.Kind) = To_String (Value.Improve_Task_Id) then
                     if Field (Payload, "harness_id") /= To_String (Value.Harness_Task_Id) or else
                       Field (Payload, "origin") /= To_String (Value.Origin)
                     then
                        raise Data_Error with "publication reconciliation identity does not match stored mapping";
                     end if;
                     Row.State := WW (To_String (Value.State));
                     Check
                       (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Publications_Table), Row),
                        "update reconciled publication state");
                     Found := True;
                     exit;
                  end if;
               end;
               Advance (Item, Tx, Publications_Table, Cursor);
            end loop;
            if not Found then
               raise Data_Error with "publication reconciliation references an unknown Improve task";
            end if;
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
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for verification recording";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Row_Id := Next_Id (Item, Tx, Verifications_Table);
      for Value of Values loop
         declare
            Cursor   : Entity_Tables.Cursor := Scan (Item, Tx, Verifications_Table);
            Existing : Boolean := False;
            Key      : constant String := Record_Key (Value);
         begin
            if Value.Scope = Task_Evaluation and then Length (Value.Task_Id) = 0 then
               raise Data_Error with "task verification has no task identity";
            elsif Value.Scope /= Task_Evaluation and then Length (Value.Task_Id) > 0 then
               raise Data_Error with "aggregate verification must not name a task";
            end if;
            while Entity_Tables.Has_Element (Cursor) loop
               declare
                  Row     : constant Entity := Entity_Tables.Element (Cursor);
                  Payload : constant String := S (Row.Payload);
               begin
                  if S (Row.Kind) = Key and then Field (Payload, "plan_id") = Plan_Id and then
                    Field (Payload, "assessment_id") = Number (Value.Assessment_Id) and then
                    Field_Or (Payload, "plan_revision", "1") = Number (Value.Plan_Revision) and then
                    Field_Or (Payload, "contract", "") = To_String (Value.Contract_Fingerprint)
                  then
                     if S (Row.State) /= Improve.Model.Image (Value.Outcome) or else
                       Field_Or (Payload, "scope", "task") /= Scope_Image (Value.Scope) or else
                       Field (Payload, "comparable") /= Boolean_Image (Value.Comparable) or else
                       Field (Payload, "explanation") /= To_String (Value.Explanation)
                     then
                        raise Data_Error with "verification evidence conflicts for task and assessment";
                     end if;
                     Existing := True;
                     exit;
                  end if;
               end;
               Advance (Item, Tx, Verifications_Table, Cursor);
            end loop;
            if not Existing then
               Check
                 (Entity_Tables.Insert
                    (Tx, Item.DB, Item.Schemas (Verifications_Table),
                     (Row_Id, 0, WW (Key), WW (Improve.Model.Image (Value.Outcome)),
                      WW (Pair ("plan_id", Plan_Id) & LF &
                          Pair ("assessment_id", Number (Value.Assessment_Id)) & LF &
                          Pair ("plan_revision", Number (Value.Plan_Revision)) & LF &
                          Pair ("contract", To_String (Value.Contract_Fingerprint)) & LF &
                          Pair ("scope", Scope_Image (Value.Scope)) & LF &
                          Pair ("task_id", To_String (Value.Task_Id)) & LF &
                          Pair ("comparable", Boolean_Image (Value.Comparable)) & LF &
                          Pair ("explanation", To_String (Value.Explanation))), True, Verifications_Table)),
                  "record verification evidence");
               Row_Id := Row_Id + 1;
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
      Task_Id : String := "") return Verification_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Result : Verification_Vectors.Vector;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Cursor := Scan (Item, Tx, Verifications_Table);
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row     : constant Entity := Entity_Tables.Element (Cursor);
            Payload : constant String := S (Row.Payload);
            Scope   : constant Verification_Scope := Parse_Scope (Field_Or (Payload, "scope", "task"));
            Stored_Task : constant String :=
              (if Scope = Task_Evaluation then Field_Or (Payload, "task_id", S (Row.Kind)) else "");
         begin
            if (Plan_Id = "" or else Field (Payload, "plan_id") = Plan_Id) and then
              (Task_Id = "" or else (Scope = Task_Evaluation and then Stored_Task = Task_Id))
            then
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
         end;
         Advance (Item, Tx, Verifications_Table, Cursor);
      end loop;
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
      Revision : Positive) is
      Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision);
      Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
      Tx     : Database.Transactions.Transaction;
      Row_Id : Positive;
   begin
      if not Item.Opened or else not Item.Writable then
         raise Data_Error with "Improve state is not open for plan approval";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
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
            Advance (Item, Tx, Operations_Table, Cursor);
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
      Revision : Positive) return Boolean is
      Plan   : constant Improve.Model.Plan_Revision := Load (Item, Plan_Id, Revision);
      Key    : constant String := "approve:" & Plan_Id & ":" & Number (Revision);
      Tx     : Database.Transactions.Transaction;
      Result : Boolean := False;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
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
            Advance (Item, Tx, Operations_Table, Cursor);
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
      Task_Ids : Improve.Model.UString_Vectors.Vector) return Positive is
      Stored  : constant Improve.Model.Plan_Revision :=
        Load (Item, To_String (Plan.Plan_Id), Plan.Revision);
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
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if S (Row.Kind) = Key and then S (Row.State) = "started" then
                  Database.Transactions.Rollback (Tx);
                  return Row.Id;
               end if;
            end;
            Advance (Item, Tx, Operations_Table, Cursor);
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
      declare Cursor : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Id = Operation_Id and then S (Row.State) = "started" then
                  Started := Row;
                  Found := True;
               elsif Row.Parent_Id = Operation_Id and then S (Row.State) = "completed" then
                  Database.Transactions.Rollback (Tx);
                  return;
               end if;
            end;
            Advance (Item, Tx, Operations_Table, Cursor);
         end loop;
      end;
      if not Found then raise Data_Error with "unknown publication operation"; end if;
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

   function Pending_Publications (Item : in out Store) return Operation_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Result : Operation_Vectors.Vector;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      declare Starts : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
         while Entity_Tables.Has_Element (Starts) loop
            declare
               Row       : constant Entity := Entity_Tables.Element (Starts);
               Completed : Boolean := False;
            begin
               if S (Row.State) = "started" then
                  declare Ends : Entity_Tables.Cursor := Scan (Item, Tx, Operations_Table); begin
                     while Entity_Tables.Has_Element (Ends) loop
                        if Entity_Tables.Element (Ends).Parent_Id = Row.Id and then
                          S (Entity_Tables.Element (Ends).State) = "completed"
                        then
                           Completed := True;
                           exit;
                        end if;
                        Advance (Item, Tx, Operations_Table, Ends);
                     end loop;
                  end;
                  if not Completed then
                     declare Payload : constant String := S (Row.Payload); begin
                        Result.Append
                          (Operation_Record'
                             (Id       => Row.Id,
                              Key      => To_Unbounded_String (S (Row.Kind)),
                              Plan_Id  => To_Unbounded_String (Field (Payload, "plan_id")),
                              Revision => Positive'Value (Field_Or (Payload, "revision", "1")),
                              Fingerprint => To_Unbounded_String (Field_Or (Payload, "fingerprint", "")),
                              Task_Ids => Unpack (Field (Payload, "task_ids"))));
                     end;
                  end if;
               end if;
            end;
            Advance (Item, Tx, Operations_Table, Starts);
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
