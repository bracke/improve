with Ada.Strings.Unbounded;

--  User-visible messages rendered through the shared messages library.
package Improve.Text is
   --  Message-catalog facade for every user-visible string.

   type Argument is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  Named message interpolation value.
   --  @field Name Placeholder name.
   --  @field Value Replacement value.

   type Argument_List is array (Positive range <>) of Argument;
   --  Message interpolation arguments.

   No_Arguments : constant Argument_List (1 .. 0) := [others => <>];
   --  Empty argument list.

   function Arg (Name, Value : String) return Argument;
   --  Construct a message argument.
   --  @param Name Placeholder name.
   --  @param Value Replacement value.
   --  @return Owned message argument.

   function Message (Key : String; Args : Argument_List := No_Arguments) return String;
   --  Render a localized catalog message.
   --  @param Key Stable catalog key.
   --  @param Args Named interpolation values.
   --  @return Rendered user-visible message.

   function Catalog_Is_Valid return Boolean;
   --  Validate the embedded message catalog.
   --  @return True when all catalog entries and placeholders are valid.
end Improve.Text;

