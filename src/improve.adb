with Ada.Streams;
with CryptoLib.Hashes;

package body Improve with SPARK_Mode is
   function Calculate_SHA256
     (Data : Ada.Streams.Stream_Element_Array) return CryptoLib.Hashes.SHA256_Digest
     with Global => null;

   function Calculate_SHA256
     (Data : Ada.Streams.Stream_Element_Array) return CryptoLib.Hashes.SHA256_Digest
     with SPARK_Mode => Off is
   begin
      return CryptoLib.Hashes.SHA256 (Data);
   end Calculate_SHA256;

   function Stable_Digest (Text : String) return String is
      use Ada.Streams;
      Data       : Stream_Element_Array (1 .. Text'Length) := [others => 0];
      Digest     : CryptoLib.Hashes.SHA256_Digest;
      Hex_Digits : constant String := "0123456789abcdef";
      Result     : String (1 .. 71) := "sha256:" & [1 .. 64 => '0'];
   begin
      for Index in Text'Range loop
         Data (Stream_Element_Offset (Index - Text'First + 1)) := Stream_Element (Character'Pos (Text (Index)));
      end loop;
      Digest := Calculate_SHA256 (Data);
      for Index in Digest'Range loop
         Result (8 + 2 * (Index - Digest'First)) := Hex_Digits (Natural (Digest (Index)) / 16 + 1);
         Result (9 + 2 * (Index - Digest'First)) := Hex_Digits (Natural (Digest (Index)) mod 16 + 1);
      end loop;
      return Result;
   end Stable_Digest;
end Improve;

