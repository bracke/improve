--  Schema ownership and migration fixtures for storage tests.
package Improve.Storage.Schema_Testing is
   procedure Create_Foreign_Database (Path : String);
   --  Create an empty dependency-owned database without Improve schema objects.
   --  @param Path New database path.

   function Has_Improve_Table (Path : String) return Boolean;
   --  Test whether a database exposes the Improve physical table without modifying it.
   --  @param Path Existing database path.
   --  @return Whether the Improve table exists.

   procedure Corrupt_Schema_Ownership (Path : String);
   --  Replace Improve schema ownership metadata with a foreign marker.
   --  @param Path Existing writable Improve database.

   procedure Downgrade_To_Version_2 (Path : String);
   --  Destructively convert a current test database into the supported version-2 fixture shape.
   --  @param Path Existing writable Improve database.

   procedure Downgrade_To_Version_3 (Path : String);
   --  Destructively convert a current test database into the supported version-3 fixture shape.
   --  @param Path Existing writable Improve database.

   procedure Downgrade_To_Version_6 (Path : String);
   --  Destructively convert a current test database into the supported version-6 fixture shape.
   --  @param Path Existing writable Improve database.
end Improve.Storage.Schema_Testing;
