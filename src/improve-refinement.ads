with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Interfaces;
with Improve.Model;

--  Optional agent refinement behind a bounded, typed, noninteractive adapter.
package Improve.Refinement is
   --  Bounded typed context construction and validation for optional agent refinement.

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized refinement text.

   type Limits is record
      Maximum_Context_Bytes     : Positive := 131_072;
      Maximum_File_Bytes        : Positive := 32_768;
      Maximum_Response_Bytes    : Positive := 131_072;
      Timeout_Seconds           : Positive := 60;
      Maximum_Findings_Per_Task : Positive := 50;
      Maximum_Tasks             : Positive := 100;
   end record;
   --  Bounded refinement inputs independent of application configuration.
   --  @field Maximum_Context_Bytes Maximum context supplied to an adapter.
   --  @field Maximum_File_Bytes Maximum bytes read from one source file.
   --  @field Maximum_Response_Bytes Maximum accepted structured response bytes.
   --  @field Timeout_Seconds Adapter request deadline.
   --  @field Maximum_Findings_Per_Task Maximum proposed evidence and file references.
   --  @field Maximum_Tasks Maximum proposal and dependency count.

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
      Evidence         : Improve.Model.Finding_Vectors.Vector;
      Draft_Tasks      : Improve.Model.Task_Vectors.Vector;
      Existing_Tasks   : Improve.Model.Task_Vectors.Vector;
      Required_Schema  : UString;
      Sources          : Source_Vectors.Vector;
      Evidence_Truncated       : Boolean := False;
      Draft_Tasks_Truncated    : Boolean := False;
      Existing_Tasks_Truncated : Boolean := False;
      Byte_Count       : Natural := 0;
      Maximum_Response_Bytes : Positive := 131_072;
   end record;
   --  Bounded, read-only material supplied to an adapter.
   --  @field Project_Id Target project identity.
   --  @field Project_Name Target project name.
   --  @field Project_Root Canonical target root.
   --  @field Assessment_Run Originating assessment identity.
   --  @field Policy Quality policy fingerprint.
   --  @field Toolchain Toolchain fingerprint.
   --  @field Evidence Typed normalized measurement evidence. Descriptive text is untrusted data.
   --  @field Draft_Tasks Typed deterministic task specifications.
   --  @field Existing_Tasks Typed existing related work.
   --  @field Required_Schema Structured response contract.
   --  @field Sources Authorized source excerpts.
   --  @field Evidence_Truncated Whether the evidence collection was bounded.
   --  @field Draft_Tasks_Truncated Whether deterministic tasks were bounded.
   --  @field Existing_Tasks_Truncated Whether existing tasks were bounded.
   --  @field Byte_Count Total context size.
   --  @field Maximum_Response_Bytes Maximum structured response accepted from the provider.

   function Response_Schema return String;
   --  Return the exact JSON Schema required for a refinement response.
   --  @return Stable schema for an object containing typed task proposals.

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
   --  Structured refinement of one deterministic task. Execution text, evidence identity, category, and mandatory
   --  acceptance remain validator-controlled; addendum fields are reserved and must be empty.
   --  @field Task_Id Target Improve task identity.
   --  @field Category Proposed category, which must remain compatible.
   --  @field Title Deterministic title, which must remain unchanged.
   --  @field Goal_Addendum Reserved; must be empty.
   --  @field Scope_Addendum Reserved; must be empty.
   --  @field Acceptance_Addendum Reserved; must be empty.
   --  @field Verification_Addendum Reserved; must be empty.
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

   Adapter_Error : exception;
   --  Documented recoverable adapter-boundary failure.

   function Name (Self : Adapter) return String is abstract;
   --  Return a stable adapter identity used in plan provenance.
   --  @param Self Adapter instance.
   --  @return Stable adapter identity.

   type Adapter_Provenance is record
      Provider_Id    : UString;
      Model_SHA256   : UString;
      Canonical_Path : UString;
      Model_Name     : UString;
      Architecture   : UString;
      Model_Bytes    : Interfaces.Unsigned_64 := 0;
      Model_Parts    : Natural := 0;
   end record;
   --  Typed identity and diagnostic material for an accepted refinement.
   --  @field Provider_Id Stable provider implementation identity.
   --  @field Model_SHA256 Exact model digest, or empty when unavailable.
   --  @field Canonical_Path Canonical backbone path, or empty when unavailable.
   --  @field Model_Name Model title supplied by the GGUF metadata, or empty.
   --  @field Architecture Stable model architecture identifier, or empty.
   --  @field Model_Bytes Total bytes across opened model files.
   --  @field Model_Parts Number of opened model files.

   function Provenance (Self : Adapter) return Adapter_Provenance is abstract;
   --  Return typed provider provenance.
   --  @param Self Adapter instance.
   --  @return Provider and model identity for accepted plans.

   function Cancellation_Requested (Self : Adapter) return Boolean is abstract;
   --  Return whether the caller cooperatively cancelled this adapter.
   --  @param Self Adapter instance.
   --  @return True when the enclosing operation must stop without persistence.

   procedure Request
     (Self            : in out Adapter;
      Context         : Planning_Context;
      Timeout_Seconds : Positive;
      Response        : out Agent_Response) is abstract;
   --  Return structured proposals without changing project or harness state. The adapter must enforce the
   --  supplied deadline cooperatively and return Agent_Timed_Out when it expires; Request is never aborted
   --  asynchronously by Improve.
   --  @param Self Adapter instance.
   --  @param Context Bounded immutable planning context.
   --  @param Timeout_Seconds Request deadline.
   --  @param Response Structured response receiver.
   --  @exception Adapter_Error The provider failed before it could return a structured status.

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
      Settings       : Limits;
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
      Settings       : Limits;
      Provider       : not null access Adapter'Class;
      Existing_Tasks : Improve.Model.Task_Vectors.Vector := Improve.Model.Task_Vectors.Empty_Vector)
      return Refinement_Result;
   --  Request and validate optional refinement. Documented Adapter_Error failures and rejected proposals return
   --  the unchanged deterministic draft; programming and resource failures propagate to the caller.
   --  @param Draft Deterministic plan draft.
   --  @param Settings Validated refinement limits.
   --  @param Provider Noninteractive adapter.
   --  @param Existing_Tasks Existing related work.
   --  @return Validated refinement result.
end Improve.Refinement;
