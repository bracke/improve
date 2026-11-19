with Ada.Strings.Unbounded;

package body Improve.Refinement.Model_Adapter is
   use Ada.Strings.Unbounded;

   overriding function Name (Self : Provider) return String is
     ("model:" & Model_Adapter.Name (Self.Backend.all));

   overriding function Provenance
     (Self : Provider) return Improve.Refinement.Adapter_Provenance is
      Result : Improve.Refinement.Adapter_Provenance := Details (Self.Backend.all);
   begin
      Result.Provider_Id := To_Unbounded_String (Name (Self));
      Result.Model_SHA256 := To_Unbounded_String (Model_SHA256 (Self.Backend.all));
      return Result;
   end Provenance;

   overriding function Cancellation_Requested (Self : Provider) return Boolean is
     (Model_Adapter.Cancellation_Requested (Self.Backend.all));

   overriding procedure Request
     (Self            : in out Provider;
      Context         : Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Agent_Response) is
   begin
      if Length (Context.Required_Schema) = 0 then
         raise Adapter_Error with "model refinement requires an answer schema";
      end if;
      Complete
        (Self.Backend.all, Context, To_String (Context.Required_Schema), Timeout_Seconds,
         Maximum_Response_Bytes => Context.Maximum_Response_Bytes, Response => Response);
   end Request;
end Improve.Refinement.Model_Adapter;
