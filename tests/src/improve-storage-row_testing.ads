--  Row inspection and corruption fixtures for storage tests.
package Improve.Storage.Row_Testing is
   function Summary_Row_Bytes (Path : String; Revision_Id : Positive) return Positive;
   --  Measure encoded rows consumed while reconstructing one persisted summary.
   --  @param Path Existing Improve database.
   --  @param Revision_Id Logical revision row identity.
   --  @return Aggregate encoded bytes for the summary fixture rows.

   procedure Corrupt_Revision (Path : String; Revision_Id : Positive);
   --  Replace one revision payload with a malformed representation.
   --  @param Path Existing writable Improve database.
   --  @param Revision_Id Logical revision row identity.

   procedure Corrupt_Baseline_Parent (Path : String; Baseline_Id : Positive);
   --  Replace one baseline parent with a nonexistent project identity.
   --  @param Path Existing writable Improve database.
   --  @param Baseline_Id Logical baseline row identity.

   procedure Replace_Row_Payload (Path : String; Table, Id : Positive; Payload : String);
   --  Destructively replace a logical row payload.
   --  @param Path Existing writable Improve database.
   --  @param Table Logical table identity.
   --  @param Id Logical row identity.
   --  @param Payload Replacement UTF-8 payload.

   procedure Replace_Row_State (Path : String; Table, Id : Positive; State : String);
   --  Destructively replace a logical row state.
   --  @param Path Existing writable Improve database.
   --  @param Table Logical table identity.
   --  @param Id Logical row identity.
   --  @param State Replacement UTF-8 state.

   procedure Deactivate_Row (Path : String; Table, Id : Positive);
   --  Mark a logical row inactive without changing its content.
   --  @param Path Existing writable Improve database.
   --  @param Table Logical table identity.
   --  @param Id Logical row identity.

   procedure Append_Task_Payload_Field (Path : String; Task_Row : Positive; Name, Value : String);
   --  Append a raw field to one task payload without canonicalization.
   --  @param Path Existing writable Improve database.
   --  @param Task_Row Logical task row identity.
   --  @param Name Field name.
   --  @param Value Field value.

   procedure Duplicate_Row (Path : String; Table, Source_Id, New_Id : Positive);
   --  Clone one logical row under a caller-selected identity.
   --  @param Path Existing writable Improve database.
   --  @param Table Logical table identity.
   --  @param Source_Id Existing logical row identity.
   --  @param New_Id Clone logical row identity.

   procedure Duplicate_Plan (Path : String; Task_Count : Positive);
   --  Clone the first plan, revision, and requested tasks into an ambiguous plan fixture.
   --  @param Path Existing writable Improve database.
   --  @param Task_Count Number of leading task rows to clone.

   procedure Insert_Unknown_Finding_Link (Path : String; Task_Row : Positive);
   --  Insert a task link referencing a nonexistent finding.
   --  @param Path Existing writable Improve database.
   --  @param Task_Row Owning logical task row identity.

   procedure Insert_Duplicate_Task_Detail (Path : String; Task_Row : Positive);
   --  Insert a conflicting normalized goal detail for one task.
   --  @param Path Existing writable Improve database.
   --  @param Task_Row Owning logical task row identity.
end Improve.Storage.Row_Testing;
