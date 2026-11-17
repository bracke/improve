with Ada.Streams;

package body Improve.Canonical_Digests is
   procedure Append (Item : in out Builder; Text : String) is
      use Ada.Streams;
      Buffer : Stream_Element_Array (1 .. 65_536);
      First  : Natural := Text'First;
   begin
      while First <= Text'Last loop
         declare
            Count : constant Natural := Natural'Min (Buffer'Length, Text'Last - First + 1);
         begin
            for Offset in 0 .. Count - 1 loop
               Buffer (Buffer'First + Stream_Element_Offset (Offset)) :=
                 Stream_Element (Character'Pos (Text (First + Offset)));
            end loop;
            CryptoLib.Hashes.Update
              (Item.Context, Buffer (Buffer'First .. Buffer'First + Stream_Element_Offset (Count) - 1));
            First := First + Count;
         end;
      end loop;
   end Append;

   procedure Initialize
     (Item                : out Builder;
      Domain              : String := "";
      Maximum_Value_Bytes : Natural := Natural'Last) is
   begin
      CryptoLib.Hashes.Initialize_SHA256 (Item.Context);
      Item.Maximum_Value_Bytes := Maximum_Value_Bytes;
      Item.Used_Value_Bytes := 0;
      Item.Initialized := True;
      Append (Item, Domain);
   end Initialize;

   procedure Add (Item : in out Builder; Name, Value : String) is
   begin
      if not Item.Initialized then
         raise Program_Error with "canonical digest builder is not initialized";
      elsif Value'Length > Item.Maximum_Value_Bytes - Item.Used_Value_Bytes then
         raise Data_Error with "canonical digest exceeds configured value-byte limit";
      end if;
      Item.Used_Value_Bytes := Item.Used_Value_Bytes + Value'Length;
      Append (Item, Natural'Image (Name'Length) & ":" & Name);
      Append (Item, Natural'Image (Value'Length) & ":" & Value);
   end Add;

   function Finish (Item : in out Builder; Prefix : String := "sha256:") return String is
   begin
      if not Item.Initialized then
         raise Program_Error with "canonical digest builder is not initialized";
      end if;
      declare
         Digest : constant CryptoLib.Hashes.SHA256_Digest := CryptoLib.Hashes.Finalize (Item.Context);
         Hex    : constant String := "0123456789abcdef";
         Result : String (1 .. Prefix'Length + 2 * Digest'Length);
         Cursor : Natural := Result'First;
      begin
         if Prefix /= "" then
            Result (Cursor .. Cursor + Prefix'Length - 1) := Prefix;
            Cursor := Cursor + Prefix'Length;
         end if;
         for Value of Digest loop
            Result (Cursor) := Hex (Natural (Value) / 16 + 1);
            Result (Cursor + 1) := Hex (Natural (Value) mod 16 + 1);
            Cursor := Cursor + 2;
         end loop;
         Item.Initialized := False;
         return Result;
      end;
   end Finish;
end Improve.Canonical_Digests;
