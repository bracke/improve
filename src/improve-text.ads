with Ada.Strings.Unbounded;

--  User-visible messages rendered through the shared messages library.
package Improve.Text is
   type Argument is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   type Argument_List is array (Positive range <>) of Argument;
   No_Arguments : constant Argument_List (1 .. 0) := [others => <>];

   function Arg (Name, Value : String) return Argument;
   function Message (Key : String; Args : Argument_List := No_Arguments) return String;
   function Catalog_Is_Valid return Boolean;
end Improve.Text;

