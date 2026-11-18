with Ada.Strings.Unbounded;

package body Improve.Refinement.Model_Adapter is
   use Ada.Strings.Unbounded;

   overriding function Name (Self : Provider) return String is
     ("model:" & Model_Adapter.Name (Self.Backend.all));

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
