with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Model;

--  Optional agent refinement behind a bounded, typed, noninteractive adapter.
package Improve.Refinement is
   --  Bounded typed context construction and validation for optional agent refinement.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized refinement text.

   type Source_State is
     (Source_Available, Source_Missing, Source_Outside, Source_Too_Large, Source_Not_File, Source_Read_Failed);
   --  Result of an authorized no-follow source read.
   --  @enum Source_Available Source content was read.
   --  @enum Source_Missing Referenced source does not exist.
   --  @enum Source_Outside Path escapes the project root.
   --  @enum Source_Too_Large Source exceeds the configured limit.
   --  @enum Source_Not_File Path does not name an ordinary file.
   --  @enum Source_Read_Failed Source could not be read safely.

   function Image (Value : Source_State) return String;
   --  Return the stable lowercase source-state spelling.
   --  @param Value Source state.
   --  @return Stable lowercase spelling.

   type Source_Excerpt is record
      Relative_Path : UString;
      Content       : UString;
      State         : Source_State := Source_Missing;
      Truncated     : Boolean := False;
   end record;
   --  One bounded source input supplied to refinement.
   --  @field Relative_Path Authorized project-relative path.
   --  @field Content Bounded source text when available.
   --  @field State Read result.
   --  @field Truncated Whether content was deliberately shortened.

   package Source_Vectors is new Ada.Containers.Vectors (Positive, Source_Excerpt);
   --  Ordered source excerpts.

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
   --  @field Project_Id Target project identity.
   --  @field Project_Name Target project name.
   --  @field Project_Root Canonical target root.
   --  @field Assessment_Run Originating assessment identity.
   --  @field Policy Quality policy fingerprint.
   --  @field Toolchain Toolchain fingerprint.
   --  @field Evidence Normalized measurement evidence.
   --  @field Draft_Tasks Deterministic task specifications.
   --  @field Existing_Tasks Existing related work.
   --  @field Required_Schema Structured response contract.
   --  @field Sources Authorized source excerpts.
   --  @field Byte_Count Total context size.

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
   --  @field Task_Id Target Improve task identity.
   --  @field Category Proposed category, which must remain compatible.
   --  @field Title Refined title.
   --  @field Goal_Addendum Additional goal detail.
   --  @field Scope_Addendum Additional bounded scope.
   --  @field Acceptance_Addendum Additional acceptance criteria.
   --  @field Verification_Addendum Additional verification detail.
   --  @field Relevant_Files Proposed authorized source paths.
   --  @field Dependencies Proposed task prerequisites.
   --  @field Finding_Keys Referenced evidence identities.
   --  @field Confidence Proposed confidence percentage.
   --  @field Preserves_Quality_Policy Explicit quality-policy preservation claim.

   package Proposal_Vectors is new Ada.Containers.Vectors (Positive, Task_Proposal);
   --  Ordered structured task proposals.

   type Response_Status is (Proposal_Ready, Agent_Unavailable, Agent_Timed_Out, Malformed_Response);
   --  Adapter response state.
   --  @enum Proposal_Ready Structured proposals are available.
   --  @enum Agent_Unavailable Adapter could not provide a response.
   --  @enum Agent_Timed_Out Adapter exceeded its deadline.
   --  @enum Malformed_Response Response could not satisfy the structured contract.

   type Agent_Response is record
      Status     : Response_Status := Agent_Unavailable;
      Proposals  : Proposal_Vectors.Vector;
      Diagnostic : UString;
   end record;
   --  Complete bounded adapter response.
   --  @field Status Response state.
   --  @field Proposals Structured task proposals.
   --  @field Diagnostic Bounded adapter diagnostic.

   type Adapter is limited interface;
   --  Noninteractive refinement provider contract.

   function Name (Self : Adapter) return String is abstract;
   --  Return a stable adapter identity used in plan provenance.
   --  @param Self Adapter instance.
   --  @return Stable adapter identity.

   procedure Request
     (Self            : in out Adapter;
      Context         : Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Agent_Response) is abstract;
   --  Return structured proposals without changing project or harness state.
   --  @param Self Adapter instance.
   --  @param Context Bounded immutable planning context.
   --  @param Timeout_Seconds Request deadline.
   --  @param Response Structured response receiver.

   type Refinement_Status is
     (Refined, Unavailable_Fallback, Timeout_Fallback, Malformed_Fallback, Rejected_Fallback,
      Adapter_Error_Fallback);
   --  Deterministic refinement result state.
   --  @enum Refined Validated proposals were applied.
   --  @enum Unavailable_Fallback Deterministic draft retained because the adapter was unavailable.
   --  @enum Timeout_Fallback Deterministic draft retained after timeout.
   --  @enum Malformed_Fallback Deterministic draft retained after malformed output.
   --  @enum Rejected_Fallback Deterministic draft retained after validation rejected proposals.
   --  @enum Adapter_Error_Fallback Deterministic draft retained after adapter failure.

   function Image (Value : Refinement_Status) return String;
   --  Return the stable lowercase refinement status.
   --  @param Value Refinement status.
   --  @return Stable lowercase spelling.

   type Refinement_Result is record
      Plan       : Improve.Model.Plan_Revision;
      Status     : Refinement_Status := Unavailable_Fallback;
      Diagnostic : UString;
   end record;
   --  Validated plan and refinement disposition.
   --  @field Plan Refined or unchanged deterministic plan.
   --  @field Status Refinement disposition.
   --  @field Diagnostic Validation or fallback explanation.

   function Build_Context
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Planning_Context;
   --  Build bounded evidence and source context. Source reads are rooted,
   --  no-follow reads and never escape the registered project directory.
   --  @param Draft Deterministic plan draft.
   --  @param Settings Validated refinement limits.
   --  @param Existing_Tasks Existing related work.
   --  @return Bounded planning context.

   function Refine
     (Draft          : Improve.Model.Plan_Revision;
      Settings       : Improve.Config.Settings;
      Provider       : not null access Adapter'Class;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Refinement_Result;
   --  Request and validate optional refinement. Every adapter failure or
   --  rejected proposal returns the unchanged deterministic draft.
   --  @param Draft Deterministic plan draft.
   --  @param Settings Validated refinement limits.
   --  @param Provider Noninteractive adapter.
   --  @param Existing_Tasks Existing related work.
   --  @return Validated refinement result.
end Improve.Refinement;
