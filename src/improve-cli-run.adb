separate (Improve.CLI)
function Run
  (Provider : access Improve.Refinement.Adapter'Class) return Natural is
   Arguments : String_Vectors.Vector;
begin
   for Index in 1 .. Ada.Command_Line.Argument_Count loop
      Arguments.Append (Ada.Command_Line.Argument (Index));
   end loop;
   declare
      Result : constant Outcome := Execute (Arguments, Provider);
   begin
      if Length (Result.Errors) > 0 then
         Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, To_String (Result.Errors));
      end if;
      if Length (Result.Output) > 0 then Write (To_String (Result.Output)); end if;
      return Result.Exit_Code;
   exception
      when Error : Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.Use_Error | Ada.IO_Exceptions.End_Error |
           Ada.IO_Exceptions.Status_Error =>
         Ada.Text_IO.Put
           (Ada.Text_IO.Standard_Error,
            Diagnostic
              (Invalid_State,
               Message ("error.output", [Arg ("message", Ada.Exceptions.Exception_Message (Error))])));
         return Failure_Exit;
   end;
end Run;
