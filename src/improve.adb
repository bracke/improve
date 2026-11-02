with Interfaces;

package body Improve is
   function Stable_Digest (Text : String) return String is
      use type Interfaces.Unsigned_64;
      Value  : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Hex_Digits : constant String := "0123456789abcdef";
      Result : String (1 .. 24) := "fnv1a64:0000000000000000";
      Work   : Interfaces.Unsigned_64;
   begin
      for Byte of Text loop
         Value := (Value xor Interfaces.Unsigned_64 (Character'Pos (Byte))) * 16#100000001B3#;
      end loop;
      Work := Value;
      for Index in reverse 9 .. Result'Last loop
         Result (Index) := Hex_Digits (Natural (Work and 16#F#) + 1);
         Work := Interfaces.Shift_Right (Work, 4);
      end loop;
      return Result;
   end Stable_Digest;
end Improve;

