with Ada.Calendar;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Improve;
with Improve.Model;
with Improve.Storage_Codec;

package body Improve_Storage_Codec_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use type Improve.Model.UString_Vectors.Vector;

   type Codec_Case is new AUnit.Simple_Test_Cases.Test_Case with null record;
   type Codec_Access is access all Codec_Case;
   overriding function Name (Item : Codec_Case) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Codec_Case);

   overriding function Name (Item : Codec_Case) return AUnit.Message_String is
      pragma Unreferenced (Item);
   begin
      return AUnit.Format ("IMP_STORAGE_CODEC_BOUNDARIES");
   end Name;

   overriding procedure Run_Test (Item : in out Codec_Case) is
      pragma Unreferenced (Item);
      Values  : Improve.Model.UString_Vectors.Vector;
      Invalid : Boolean := False;
   begin
      Assert
        (Improve.Storage_Codec.Decode (Improve.Storage_Codec.Encode ("Ada")) = "Ada" and then
         Improve.Storage_Codec.S (Improve.Storage_Codec.WW ("Improve")) = "Improve",
         "storage text codec did not round-trip");
      Assert
        (Improve.Storage_Codec.Number (42) = "42" and then
         Improve.Storage_Codec.Boolean_Image (True) = "true" and then
         Improve.Storage_Codec.Boolean_Image (False) = "false",
         "storage scalar images are not canonical");
      Assert
        (Improve.Storage_Codec.Id_Image ("IMP-", 7) = "IMP-000007" and then
         Improve.Storage_Codec.Plan_Row_Id ("PLAN-000042") = 42,
         "storage identities did not round-trip");
      declare
         Image : constant String := Improve.Storage_Codec.Timestamp (Ada.Calendar.Clock);
      begin
         Assert
           (Improve.Storage_Codec.Timestamp (Improve.Storage_Codec.Parse_Time (Image)) = Image,
            "storage timestamp did not round-trip");
      end;
      Values.Append (To_Unbounded_String ("alpha"));
      Values.Append (To_Unbounded_String ("line" & Character'Val (10) & "slash\"));
      declare
         Packed  : constant String := Improve.Storage_Codec.Pack (Values);
         Decoded : constant Improve.Model.UString_Vectors.Vector := Improve.Storage_Codec.Unpack (Packed);
         Payload : constant String := Improve.Storage_Codec.Pair ("value", To_String (Values.Last_Element));
         With_CR : constant String := Improve.Storage_Codec.Pair ("value", "left" & Character'Val (13) & "right");
      begin
         Assert (Decoded = Values, "storage list codec did not round-trip");
         Assert
           (Improve.Storage_Codec.Field (Payload, "value") = To_String (Values.Last_Element),
            "storage field codec did not round-trip escaped text");
         Assert
           (Improve.Storage_Codec.Has_Field (Payload, "value") and then
            not Improve.Storage_Codec.Has_Field (Payload, "missing") and then
            Improve.Storage_Codec.Field_Or (Payload, "missing", "fallback") = "fallback",
            "storage field presence handling is inconsistent");
         Assert
           (Improve.Storage_Codec.Field (With_CR, "value") = "left" & Character'Val (13) & "right",
            "storage field codec did not round-trip a carriage return");
      end;
      begin
         declare
            Ignored : constant Improve.Model.UString_Vectors.Vector := Improve.Storage_Codec.Unpack ("4:abc");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted a truncated persisted list");
      Invalid := False;
      begin
         declare
            Ignored : constant String := Improve.Storage_Codec.Field ("value=\q", "value");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted an invalid escape sequence");
      Invalid := False;
      begin
         declare
            Ignored : constant Positive := Improve.Storage_Codec.Plan_Row_Id ("PLAN-broken");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Argument_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted an invalid plan identity");
      Invalid := False;
      begin
         declare
            Ignored : constant String := Improve.Storage_Codec.Field ("present=value", "missing");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted a missing required field");
      Invalid := False;
      begin
         declare
            Ignored : constant String := Improve.Storage_Codec.Field ("value=\", "value");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted a trailing escape marker");
      Invalid := False;
      begin
         declare
            Ignored : constant Improve.Model.UString_Vectors.Vector := Improve.Storage_Codec.Unpack ("x:value");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted a nonnumeric list length");
      Invalid := False;
      begin
         declare
            Ignored : constant Improve.Model.UString_Vectors.Vector :=
              Improve.Storage_Codec.Unpack ("999999999999999999999999:value");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Data_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted an overflowing list length");
      Invalid := False;
      begin
         declare
            Ignored : constant Positive := Improve.Storage_Codec.Plan_Row_Id ("invalid");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Improve.Argument_Error => Invalid := True;
      end;
      Assert (Invalid, "storage codec accepted a short plan identity");
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Codec_Access'(new Codec_Case));
      return Result;
   end Suite;
end Improve_Storage_Codec_Test_Suite;
