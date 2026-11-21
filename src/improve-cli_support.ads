with Ada.Containers;
with Improve.CLI;
with Improve.Config;

--  Shared path, limit, and presentation support for CLI command output handlers.
private package Improve.CLI_Support is
   type Read_Observer is access procedure (Completed_Pass : Positive);
   --  Internal observation seam used to exercise between-pass mutation handling.

   --  Return a Natural without the leading space used by Natural'Image.
   function Number (Value : Natural) return String;

   --  Reject a result whose item count exceeds the configured output limit.
   procedure Require_Output_Items
     (Count : Ada.Containers.Count_Type;
      Limit : Positive;
      Name  : String);

   function Page_Limit
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return Positive;
   --  Resolve and validate the requested page size against the output contract.

   function Query_Maximum
     (Item           : Improve.CLI.Invocation;
      Settings       : Improve.Config.Settings;
      Paged_Maximum  : Positive) return Positive;
   --  Select the output cap for an ordinary query or the independent domain cap for pagination.

   --  Resolve the quality database selected by an invocation and its settings.
   function Quality_Path
     (Item     : Improve.CLI.Invocation;
      Settings : Improve.Config.Settings) return String;

   --  Resolve the Improve state database selected by an invocation.
   function State_Path (Item : Improve.CLI.Invocation) return String;

   function Read_Bounded_File
     (Path          : String;
      Description   : String;
      Maximum_Bytes : Positive;
      Observer      : Read_Observer := null) return String;
   --  Read one regular input file twice from one handle, rejecting content or metadata changes between passes.
   --  Expected file-system failures are reported as Dependency_Error.

   function Read_Hex_Key
     (Path        : String;
      Description : String) return String;
   --  Read a small hexadecimal key file and remove one trailing LF or CRLF.

   --  Apply terminal styling and the optional Markdown command wrapper.
   function Render_Terminal
     (Item     : Improve.CLI.Invocation;
      Renderer : not null access function return String) return String;
end Improve.CLI_Support;
