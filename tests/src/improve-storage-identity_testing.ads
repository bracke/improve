--  Durable identity-counter fixtures for storage tests.
package Improve.Storage.Identity_Testing is
   function Identity_Counter_State (Path : String) return String;
   --  Read every durable logical identity counter as a stable semicolon-delimited value.
   --  @param Path Existing Improve database.
   --  @return Ordered counter states for all logical namespaces.

   function Task_Identity_Counter_Value (Path : String) return String;
   --  Read the durable task identity counter.
   --  @param Path Existing Improve database.
   --  @return Encoded next task identity.

   procedure Exhaust_Project_Identities (Path : String);
   --  Set the project identity counter beyond the supported logical range.
   --  @param Path Existing writable Improve database.
end Improve.Storage.Identity_Testing;
