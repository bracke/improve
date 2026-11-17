--  Shared decoding and contract validation for persisted inspection history.
separate (Improve.Storage)
package body History_Support is
   use type Improve.Model.Verification_Scope;

   procedure Select_Contracts
     (Item            : in out Store;
      Plan_Id         : String;
      Revision        : Positive;
      Limits          : Persistence_Limits;
      Cached_Plan     : in out Unbounded_String;
      Cached_Revision : in out Natural;
      Budget          : in out History_Budget;
      Contracts       : in out String_Value_Maps.Map) is
   begin
      if To_String (Cached_Plan) /= Plan_Id or else Cached_Revision /= Revision then
         Contracts.Clear;
         Cache_Contracts (Item, Plan_Id, Revision, Limits, Budget, Contracts);
         Cached_Plan := To_Unbounded_String (Plan_Id);
         Cached_Revision := Revision;
      end if;
   end Select_Contracts;

   type Publication_Position is record
      Plan_Id  : Unbounded_String;
      Revision : Positive;
      Cursor   : Publication_Envelope_Lists.Cursor;
   end record;

   function Publication_Precedes (Left, Right : Publication_Position) return Boolean is
     (Left.Plan_Id < Right.Plan_Id or else
      (Left.Plan_Id = Right.Plan_Id and then Left.Revision < Right.Revision));

   package Publication_Position_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Publication_Position);

   package Publication_Position_Sorting is new Publication_Position_Vectors.Generic_Sorting
     ("<" => Publication_Precedes);

   type Verification_Position is record
      Plan_Id  : Unbounded_String;
      Revision : Positive;
      Cursor   : Verification_Envelope_Lists.Cursor;
   end record;

   function Verification_Precedes (Left, Right : Verification_Position) return Boolean is
     (Left.Plan_Id < Right.Plan_Id or else
      (Left.Plan_Id = Right.Plan_Id and then Left.Revision < Right.Revision));

   package Verification_Position_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Verification_Position);

   package Verification_Position_Sorting is new Verification_Position_Vectors.Generic_Sorting
     ("<" => Verification_Precedes);

   function Stored_Plan_Row (Plan_Id : String) return Positive is
   begin
      return Plan_Row_Id (Plan_Id);
   exception
      when Argument_Error =>
         raise Data_Error with "persisted history has a malformed plan identity";
   end Stored_Plan_Row;

   procedure Require_Relationship
     (Item    : Store;
      Row     : Entity;
      Plan_Id : String;
      Context : String) is
   begin
      if (Item.Schema_Version >= 3 and then Row.Parent_Id /= Stored_Plan_Row (Plan_Id)) or else
        (Item.Schema_Version < 3 and then Row.Parent_Id /= 0)
      then
         raise Data_Error with Context & " has an inconsistent plan relationship";
      end if;
   end Require_Relationship;

   procedure Decode_Publication
     (Item             : Store;
      Row              : Entity;
      Expected_Plan_Id : String;
      Limits           : Persistence_Limits;
      Value            : out Publication_Envelope) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Publication_Data;
   begin
      Require_Payload_Limit (Payload, Limits, "publication mapping payload");
      Data := Improve.Persistence_Records.Decode_Publication (Payload);
      declare
         Stored_Plan : constant String := To_String (Data.Plan_Id);
         Expected    : constant String :=
           (if Expected_Plan_Id = "" then Stored_Plan else Expected_Plan_Id);
      begin
         Improve.Persistence_Validation.Validate (Data, Expected);
         Require_Relationship (Item, Row, Stored_Plan, "publication mapping");
      end;
      Value :=
        (Plan_Id => Data.Plan_Id,
         Value   =>
           (Improve_Task_Id => To_Unbounded_String (S (Row.Kind)),
            Harness_Task_Id => Data.Harness_Id,
            Origin          => Data.Origin,
            Contract        => Data.Contract,
            State           => To_Unbounded_String (S (Row.State)),
            Plan_Revision   => Data.Plan_Revision));
   end Decode_Publication;

   procedure Decode_Verification
     (Item             : Store;
      Row              : Entity;
      Expected_Plan_Id : String;
      Limits           : Persistence_Limits;
      Value            : out Verification_Envelope) is
      Payload : constant String := S (Row.Payload);
      Data    : Improve.Persistence_Records.Verification_Data;
   begin
      Require_Payload_Limit (Payload, Limits, "verification evidence payload");
      Data := Improve.Persistence_Records.Decode_Verification (Payload);
      declare
         Stored_Plan : constant String := To_String (Data.Plan_Id);
         Expected    : constant String :=
           (if Expected_Plan_Id = "" then Stored_Plan else Expected_Plan_Id);
         Stored_Task : constant Unbounded_String :=
           (if Data.Scope = Improve.Model.Task_Evaluation and then Length (Data.Task_Id) > 0
            then Data.Task_Id
            elsif Data.Scope = Improve.Model.Task_Evaluation
            then To_Unbounded_String (S (Row.Kind))
            else Null_Unbounded_String);
      begin
         Improve.Persistence_Validation.Validate
           (Data, Expected, Expected_Record_Key => S (Row.Kind));
         Require_Relationship (Item, Row, Stored_Plan, "verification evidence");
         Value :=
           (Plan_Id => Data.Plan_Id,
            Value   =>
              (Scope                => Data.Scope,
               Task_Id              => Stored_Task,
               Plan_Revision        => Data.Plan_Revision,
               Contract_Fingerprint => Data.Contract,
               Assessment_Id        => Data.Assessment_Id,
               Outcome              => Parse_Outcome (S (Row.State)),
               Comparable           => Data.Comparable,
               Explanation          => Data.Explanation));
      end;
   exception
      when Constraint_Error =>
         raise Data_Error with "stored verification evidence is malformed";
   end Decode_Verification;

   procedure Validate_Publications
     (Item     : in out Store;
      Values   : Publication_Envelope_Lists.List;
      Limits   : Persistence_Limits;
      Budget   : in out History_Budget) is
      Positions       : Publication_Position_Vectors.Vector;
      Position        : Publication_Envelope_Lists.Cursor := Values.First;
      Contracts       : String_Value_Maps.Map;
      Identities      : String_Value_Maps.Map;
      Cached_Plan     : Unbounded_String;
      Cached_Revision : Natural := 0;
   begin
      while Publication_Envelope_Lists.Has_Element (Position) loop
         declare
            Envelope : constant Publication_Envelope := Publication_Envelope_Lists.Element (Position);
         begin
            Positions.Append
              (Publication_Position'(Envelope.Plan_Id, Envelope.Value.Plan_Revision, Position));
         end;
         Publication_Envelope_Lists.Next (Position);
      end loop;
      Publication_Position_Sorting.Sort (Positions);
      for Location of Positions loop
         declare
            Envelope    : constant Publication_Envelope := Publication_Envelope_Lists.Element (Location.Cursor);
            Mapping     : Publication_Record renames Envelope.Value;
            Stored_Plan : constant String := To_String (Envelope.Plan_Id);
            Key         : constant String :=
              Contract_Key (Stored_Plan, Mapping.Plan_Revision, To_String (Mapping.Improve_Task_Id));
            Identity    : constant String :=
              Stored_Plan & Character'Val (0) & To_String (Mapping.Improve_Task_Id) &
              Character'Val (0) & To_String (Mapping.Contract);
         begin
            Select_Contracts
              (Item, Stored_Plan, Mapping.Plan_Revision, Limits,
               Cached_Plan, Cached_Revision, Budget, Contracts);
            if not Contracts.Contains (Key) then
               raise Data_Error with "publication references an unknown persisted task";
            elsif Mapping.Contract /= Contracts.Element (Key) then
               raise Data_Error with "publication does not match the persisted task contract";
            elsif Identities.Contains (Identity) then
               raise Data_Error with "duplicate persisted publication mapping";
            end if;
            Identities.Insert (Identity, Mapping.Harness_Task_Id);
         end;
      end loop;
   end Validate_Publications;

   procedure Validate_Verifications
     (Item     : in out Store;
      Values   : Verification_Envelope_Lists.List;
      Limits   : Persistence_Limits;
      Budget   : in out History_Budget) is
      Positions       : Verification_Position_Vectors.Vector;
      Position        : Verification_Envelope_Lists.Cursor := Values.First;
      Contracts       : String_Value_Maps.Map;
      Identities      : String_Value_Maps.Map;
      Cached_Plan     : Unbounded_String;
      Cached_Revision : Natural := 0;
   begin
      while Verification_Envelope_Lists.Has_Element (Position) loop
         declare
            Envelope : constant Verification_Envelope := Verification_Envelope_Lists.Element (Position);
         begin
            Positions.Append
              (Verification_Position'(Envelope.Plan_Id, Envelope.Value.Plan_Revision, Position));
         end;
         Verification_Envelope_Lists.Next (Position);
      end loop;
      Verification_Position_Sorting.Sort (Positions);
      for Location of Positions loop
         declare
            Envelope    : constant Verification_Envelope := Verification_Envelope_Lists.Element (Location.Cursor);
            Evidence    : Verification_Record renames Envelope.Value;
            Stored_Plan : constant String := To_String (Envelope.Plan_Id);
            Record_Key  : constant String :=
              (if Evidence.Scope = Improve.Model.Task_Evaluation
               then To_String (Evidence.Task_Id) else "@plan");
            Key         : constant String :=
              Contract_Key (Stored_Plan, Evidence.Plan_Revision, Record_Key);
            Identity    : constant String :=
              Stored_Plan & Character'Val (0) & Number (Evidence.Plan_Revision) & Character'Val (0) &
              Improve.Model.Image (Evidence.Scope) & Character'Val (0) & To_String (Evidence.Task_Id) &
              Character'Val (0) & Number (Evidence.Assessment_Id) & Character'Val (0) &
              To_String (Evidence.Contract_Fingerprint);
         begin
            Select_Contracts
              (Item, Stored_Plan, Evidence.Plan_Revision, Limits,
               Cached_Plan, Cached_Revision, Budget, Contracts);
            if not Contracts.Contains (Key) then
               raise Data_Error with "verification references an unknown persisted task";
            elsif Evidence.Contract_Fingerprint /= Contracts.Element (Key) then
               raise Data_Error with "verification does not match the persisted evaluation contract";
            elsif Identities.Contains (Identity) then
               raise Data_Error with "duplicate persisted verification evidence";
            end if;
            Identities.Insert (Identity, Evidence.Explanation);
         end;
      end loop;
   end Validate_Verifications;
end History_Support;
