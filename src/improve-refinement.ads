with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Model;

--  Optional agent refinement behind a bounded, typed, noninteractive adapter.
package Improve.Refinement is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   type Source_State is
     (Source_Available, Source_Missing, Source_Outside, Source_Too_Large, Source_Not_File, Source_Read_Failed);

   function Image (Value : Source_State) return String;
   --  Return the stable lowercase source-state spelling.

   type Source_Excerpt is record
      Relative_Path : UString;
      Content       : UString;
      State         : Source_State := Source_Missing;
      Truncated     : Boolean := False;
   end record;

   package Source_Vectors is new Ada.Containers.Vectors (Positive, Source_Excerpt);

   type Planning_Context is record
      Project_Id       : Positive;
      Project_Name     : UString;
      Project_Root     : UString;
      Assessment_Run   : Positive;
      Policy           : UString;
      Toolchain        : UString;
      Evidence         : UString;
      Draft_Tasks      : UString;
      Existing_Tasks   : UString;
      Required_Schema  : UString;
      Sources          : Source_Vectors.Vector;
      Byte_Count       : Natural := 0;
   end record;
   --  Bounded, read-only material supplied to an adapter.

   type Task_Proposal is record
      Task_Id                 : UString;
      Category                : UString;
      Title                   : UString;
      Goal_Addendum           : UString;
      Scope_Addendum          : UString;
      Acceptance_Addendum     : UString;
      Verification_Addendum   : UString;
      Relevant_Files          : Improve.Model.UString_Vectors.Vector;
      Dependencies            : Improve.Model.UString_Vectors.Vector;
      Finding_Keys            : Improve.Model.UString_Vectors.Vector;
      Confidence              : Natural range 0 .. 100 := 0;
      Preserves_Quality_Policy : Boolean := False;
   end record;
   --  Advisory additions to one deterministic task. Evidence identity,
   --  category, and mandatory acceptance remain validator-controlled.

   package Proposal_Vectors is new Ada.Containers.Vectors (Positive, Task_Proposal);

   type Response_Status is (Proposal_Ready, Agent_Unavailable, Agent_Timed_Out, Malformed_Response);

   type Agent_Response is record
      Status     : Response_Status := Agent_Unavailable;
      Proposals  : Proposal_Vectors.Vector;
      Diagnostic : UString;
   end record;

   type Adapter is limited interface;

   function Name (Self : Adapter) return String is abstract;
   --  Return a stable adapter identity used in plan provenance.

   procedure Request
     (Self            : in out Adapter;
      Context         : Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Agent_Response) is abstract;
   --  Return structured proposals without changing project or harness state.

   type Refinement_Status is
     (Refined, Unavailable_Fallback, Timeout_Fallback, Malformed_Fallback, Rejected_Fallback,
      Adapter_Error_Fallback);

   function Image (Value : Refinement_Status) return String;
   --  Return the stable lowercase refinement status.

   type Refinement_Result is record
      Plan       : Improve.Model.Plan_Revision;
      Status     : Refinement_Status := Unavailable_Fallback;
      Diagnostic : UString;
   end record;

   function Build_Context
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Planning_Context;
   --  Build bounded evidence and source context. Source reads are rooted,
   --  no-follow reads and never escape the registered project directory.

   function Refine
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Provider       : not null access Adapter'Class;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Refinement_Result;
   --  Request and validate optional refinement. Every adapter failure or
   --  rejected proposal returns the unchanged deterministic draft.
end Improve.Refinement;
