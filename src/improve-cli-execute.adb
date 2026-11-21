separate (Improve.CLI)
function Execute
  (Arguments : String_Vectors.Vector;
   Provider  : access Improve.Refinement.Adapter'Class) return Outcome is
   Item        : Invocation;
   Negative    : Boolean := False;
   JSON_Errors : Boolean := Requests_JSON (Arguments);
begin
   Item := Parse (Arguments);
   declare
      Configuration : constant Improve.Config.Loaded_Configuration :=
        Configuration_For (Item);
      Settings : Improve.Config.Settings renames Configuration.Values;
   begin
      if not Item.Has_Format then Item.Format := Settings.Format; end if;
      if Item.Format = DOT_Format and then
        not (Item.Command = Plan_Command and then Item.Plan_Action = Graph_Plan)
      then
         raise Argument_Error with "output format dot requires plan graph";
      end if;
      JSON_Errors := Item.Format = JSON_Format;
      if not Item.Has_Color then Item.Color := Settings.Color; end if;
      if Item.Format in JSON_Format | Markdown_Format then Item.Color := Color_Never; end if;
      declare
         Base_Output : constant String := Dispatch (Item, Configuration, Provider, Negative);
         Output      : Unbounded_String := To_Unbounded_String (Base_Output);
      begin
         if Item.Format = Terminal_Format and then Item.Quiet then
            Output := Null_Unbounded_String;
         elsif Item.Format = Terminal_Format and then Item.Verbose then
            Append
              (Output,
               Message
                 ("verbose.context",
                  [Arg ("command", Name (Item.Command)),
                   Arg ("database", Improve.Presentation.Safe_Text (Quality_Path (Item, Settings))),
                   Arg ("state", Improve.Presentation.Safe_Text (State_Path (Item)))]) & LF);
         end if;
         return
           ((if Negative then Negative_Exit else Success_Exit),
            Output, Null_Unbounded_String);
      end;
   end;
exception
   when Error : Cancelled_Error =>
      return
        (Interrupted_Exit, Null_Unbounded_String,
         To_Unbounded_String
           (Error_Output
              (Interrupted_Operation, Ada.Exceptions.Exception_Message (Error), JSON_Errors)));
   when Error : Argument_Error =>
      return
        (Argument_Exit, Null_Unbounded_String,
         To_Unbounded_String
           (Error_Output
              (Invalid_Input, Ada.Exceptions.Exception_Message (Error), JSON_Errors,
               Message ("error.hint"))));
   when Error : Dependency_Error =>
      return
        (Unavailable_Exit, Null_Unbounded_String,
         To_Unbounded_String
           (Error_Output
              (Unavailable_Dependency, Ada.Exceptions.Exception_Message (Error), JSON_Errors)));
   when Error : Data_Error =>
      return
        (Failure_Exit, Null_Unbounded_String,
         To_Unbounded_String
           (Error_Output (Invalid_State, Ada.Exceptions.Exception_Message (Error), JSON_Errors)));
   when Error : others =>
      return
        (Failure_Exit, Null_Unbounded_String,
         To_Unbounded_String
           (Error_Output (Internal_Failure, Ada.Exceptions.Exception_Message (Error), JSON_Errors)));
end Execute;
