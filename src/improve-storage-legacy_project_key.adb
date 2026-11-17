with Interfaces;

--  Reproduce the project identity used by state schemas before canonical SHA-256 identities.
separate (Improve.Storage)
function Legacy_Project_Key (Value : Improve.Model.Project_Reference) return String is
   use type Interfaces.Unsigned_64;
   Text : constant String :=
     To_String (Value.Database_Id) & Character'Val (0) & Number (Value.Id) & Character'Val (0) &
     To_String (Value.Path);
   Hash   : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
   Hex    : constant String := "0123456789abcdef";
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
