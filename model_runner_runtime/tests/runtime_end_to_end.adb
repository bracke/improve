with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with Improve.Model;
with Improve.Refinement;
with Improve.Refinement.Codec;
with Improve.Refinement.Model_Adapter;
with Improve.Refinement.Model_Runner_Client;
with Improve.Refinement.Model_Runner_Runtime;
with Jsonlib.Documents;
with Jsonlib.Serializers;
with Model_Runner.Cancellation;
with Model_Runner.Errors;
with Model_Runner.Inference;
with Model_Runner.Progress;
with Tiny_Model;

procedure Runtime_End_To_End is
   use Ada.Strings.Unbounded;
   use type Improve.Refinement.Response_Status;
   use type Improve.Refinement.Refinement_Status;
   use type Interfaces.Unsigned_64;
   use type Model_Runner.Errors.Error_Code;
   use type Model_Runner.Progress.Event_Kind;
   use type Model_Runner.Progress.Load_Stage;

   type Watcher is limited new Model_Runner.Progress.Observer with record
      Loads       : Natural := 0;
      Generations : Natural := 0;
      Hashes      : Natural := 0;
   end record;

   overriding procedure Notify
     (Self : in out Watcher;
      Item : Model_Runner.Progress.Event);

   overriding procedure Notify
     (Self : in out Watcher;
      Item : Model_Runner.Progress.Event) is
   begin
      if Item.Kind = Model_Runner.Progress.Load_Event then
         Self.Loads := Self.Loads + 1;
         if Item.Load = Model_Runner.Progress.Hashing_Model then
            Self.Hashes := Self.Hashes + 1;
         end if;
      else
         Self.Generations := Self.Generations + 1;
      end if;
   end Notify;

   type Delayer is limited new Model_Runner.Progress.Observer with record
      Delayed : Boolean := False;
   end record;

   overriding procedure Notify
     (Self : in out Delayer;
      Item : Model_Runner.Progress.Event);

   overriding procedure Notify
     (Self : in out Delayer;
      Item : Model_Runner.Progress.Event) is
   begin
      if Item.Kind = Model_Runner.Progress.Generation_Event and then not Self.Delayed then
         Self.Delayed := True;
         delay 1.1;
      end if;
   end Notify;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Answer
     (Base : Improve.Model.Task_Specification) return String
   is
      use Jsonlib.Documents;
      Doc       : Document;
      Root      : constant Node := Doc.New_Object;
      Proposals : constant Node := Doc.New_Array;
      Proposal  : constant Node := Doc.New_Object;

      function Strings
        (Values : Improve.Model.UString_Vectors.Vector) return Node
      is
         Result : constant Node := Doc.New_Array;
      begin
         for Value of Values loop
            Doc.Append (Result, Doc.New_String (To_String (Value)));
         end loop;
         return Result;
      end Strings;
   begin
      Doc.Insert (Proposal, "task_id", Doc.New_String (To_String (Base.Id)));
      Doc.Insert (Proposal, "category", Doc.New_String (To_String (Base.Category)));
      Doc.Insert (Proposal, "title", Doc.New_String (To_String (Base.Title)));
      Doc.Insert (Proposal, "goal_addendum", Doc.New_String (""));
      Doc.Insert (Proposal, "scope_addendum", Doc.New_String (""));
      Doc.Insert (Proposal, "acceptance_addendum", Doc.New_String (""));
      Doc.Insert (Proposal, "verification_addendum", Doc.New_String (""));
      Doc.Insert (Proposal, "relevant_files", Strings (Base.Relevant_Files));
      Doc.Insert (Proposal, "dependencies", Strings (Base.Dependencies));
      Doc.Insert (Proposal, "finding_keys", Strings (Base.Finding_Keys));
      Doc.Insert
        (Proposal, "confidence",
         Doc.New_Integer (Long_Long_Integer (Base.Confidence)));
      Doc.Insert
        (Proposal, "preserves_quality_policy", Doc.New_Boolean (True));
      Doc.Append (Proposals, Proposal);
      Doc.Insert (Root, "proposals", Proposals);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc);
   end Answer;

   Root : constant String :=
     Ada.Directories.Full_Name ("model_runner_runtime/tests/obj-e2e")
     & "/project";

   function Build_Draft return Improve.Model.Plan_Revision is
      Spec : Improve.Model.Task_Specification :=
        (Id              => To_Unbounded_String ("TASK-001"),
         Title           => To_Unbounded_String ("Tighten the runtime boundary"),
         Category        => To_Unbounded_String ("code"),
         Goal            => To_Unbounded_String ("Keep inference typed"),
         Problem         => To_Unbounded_String ("The boundary needs an integration test"),
         Evidence        => To_Unbounded_String ("runtime fixture"),
         Scope           => To_Unbounded_String ("target.adb"),
         Out_Of_Scope    => To_Unbounded_String ("unrelated code"),
         Requirements    => To_Unbounded_String ("preserve deterministic planning"),
         Acceptance      => To_Unbounded_String ("the typed proposal validates"),
         Verification    => To_Unbounded_String ("run the runtime integration test"),
         Confidence      => 90,
         Requires_Review => True,
         others          => <>);
      Result : Improve.Model.Plan_Revision :=
        (Plan_Id           => To_Unbounded_String ("PLAN-DRAFT-runtime"),
         Project           =>
           (Id          => 1,
            Name        => To_Unbounded_String ("runtime-fixture"),
            Path        => To_Unbounded_String (Root),
            Database_Id => To_Unbounded_String ("fixture-database")),
         Baseline          =>
           (Project_Id   => 1,
            Run_Id       => 1,
            Source_Id    => To_Unbounded_String ("source"),
            Policy_Id    => To_Unbounded_String ("policy"),
            Toolchain_Id => To_Unbounded_String ("gnat-15.2.1"),
            Evidence_Id  => To_Unbounded_String ("evidence"),
            Snapshot_Id  => To_Unbounded_String ("snapshot")),
         Working_Source_Id => To_Unbounded_String ("working-source"),
         Planner_Id        => To_Unbounded_String ("deterministic-planner"),
         Fingerprint       => To_Unbounded_String ("draft-fingerprint"),
         Review_Status     => To_Unbounded_String ("draft"),
         others            => <>);
   begin
      Spec.Relevant_Files.Append (To_Unbounded_String ("target.adb"));
      Result.Tasks.Append (Spec);
      Improve.Model.Validate (Result);
      return Result;
   end Build_Draft;

   Draft      : constant Improve.Model.Plan_Revision := Build_Draft;
   Model_Path : constant String := Root & "/runtime-model.gguf";
   Variant_Path : constant String := Root & "/runtime-model-variant.gguf";
   Malformed_Path : constant String := Root & "/runtime-model-malformed.gguf";
   Exhausted_Path : constant String := Root & "/runtime-model-exhausted.gguf";
   Corrupt_Path : constant String := Root & "/runtime-model-corrupt.gguf";
   Truncated_Path : constant String := Root & "/runtime-model-truncated.gguf";
   Unsupported_Path : constant String := Root & "/runtime-model-unsupported.gguf";
   Fuzz_Path : constant String := Root & "/runtime-model-fuzz.gguf";
   Model_Id   : constant String := "tiny-refiner";
   Seen       : aliased Watcher;
   Slow       : aliased Delayer;
   Token      : aliased Model_Runner.Cancellation.Token;
   Runtime    : aliased Improve.Refinement.Model_Runner_Runtime.Runtime;
   Status     : Model_Runner.Errors.Error_Info;
   Digest     : Model_Runner.Inference.SHA256_Hex;
   Options    : constant Model_Runner.Inference.Open_Options :=
     (Context_Tokens => 8_192,
      Observer       => Seen'Unchecked_Access,
      others         => <>);

   procedure Copy_Model
     (Source      : String;
      Target      : String;
      Maximum     : Natural := Natural'Last;
      Replace_Old : String := "";
      Replace_New : String := "") is
      use Ada.Streams;
      Input  : Stream_IO.File_Type;
      Output : Stream_IO.File_Type;
      Size   : constant Natural := Natural (Ada.Directories.Size (Source));
      Data   : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
      Last   : Stream_Element_Offset;
      Replaced : Boolean := False;
   begin
      Check
        (Replace_Old'Length = Replace_New'Length,
         "model corruption replacement changed the file length");
      Stream_IO.Open (Input, Stream_IO.In_File, Source);
      Stream_IO.Read (Input, Data, Last);
      Stream_IO.Close (Input);
      if Replace_Old /= "" then
         for Index in Data'First .. Data'Last - Stream_Element_Offset (Replace_Old'Length) + 1 loop
            declare
               Match : Boolean := True;
            begin
               for Offset in Replace_Old'Range loop
                  if Data (Index + Stream_Element_Offset (Offset - Replace_Old'First)) /=
                    Stream_Element (Character'Pos (Replace_Old (Offset)))
                  then
                     Match := False;
                     exit;
                  end if;
               end loop;
               if Match then
                  for Offset in Replace_New'Range loop
                     Data (Index + Stream_Element_Offset (Offset - Replace_New'First)) :=
                       Stream_Element (Character'Pos (Replace_New (Offset)));
                  end loop;
                  Replaced := True;
                  exit;
               end if;
            end;
         end loop;
         Check (Replaced, "model corruption fixture did not find its architecture identifier");
      end if;
      Stream_IO.Create (Output, Stream_IO.Out_File, Target);
      Stream_IO.Write
        (Output,
         Data (Data'First .. Stream_Element_Offset'Min (Last, Stream_Element_Offset (Maximum))));
      Stream_IO.Close (Output);
   end Copy_Model;

   function Run_Refinement
     (Limits : Improve.Refinement.Limits := (others => <>))
      return Improve.Refinement.Refinement_Result is
      Client : aliased Improve.Refinement.Model_Runner_Client.Client :=
        Improve.Refinement.Model_Runner_Client.Create (Runtime'Access, Model_Id);
      Provider : aliased Improve.Refinement.Model_Adapter.Provider (Client'Access);
   begin
      return Improve.Refinement.Refine (Draft, Limits, Provider'Access);
   end Run_Refinement;

   procedure Check_Format
     (Label  : String;
      Format : Tiny_Model.Weight_Format;
      Kind   : Tiny_Model.Fixture_Architecture) is
      Path : constant String := Root & "/runtime-format-" & Label & ".gguf";
   begin
      Tiny_Model.Write (Path, Room => 8_192, Format => Format, Kind => Kind);
      Improve.Refinement.Model_Runner_Runtime.Open (Runtime, Model_Id, Path, Options, Status);
      Check
        (Model_Runner.Errors.Is_Ok (Status) and then
         Improve.Refinement.Model_Runner_Runtime.Is_Open (Runtime),
         "runtime rejected supported GGUF profile " & Label & ": " &
         Model_Runner.Errors.Diagnostic_Code (Status.Code));
      Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
   end Check_Format;
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root);
   declare
      Source : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Source, Ada.Text_IO.Out_File, Root & "/target.adb");
      Ada.Text_IO.Put_Line (Source, "procedure Target is begin null; end Target;");
      Ada.Text_IO.Close (Source);
   end;

   Tiny_Model.Write
     (Model_Path,
      Room                => 8_192,
      Forced_Output       => Answer (Draft.Tasks.First_Element),
      Forced_Output_Parts => 2);
   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime, Model_Id, Model_Path, Options, Status);
   Check (Model_Runner.Errors.Is_Ok (Status), "runtime model did not open");
   Digest := Improve.Refinement.Model_Runner_Runtime.Model_SHA256 (Runtime);
   Check
     (Digest /= [1 .. 64 => '0'] and then Seen.Loads > 0 and then Seen.Hashes >= 2,
      "runtime did not retain model identity or loading progress");
   Check
     (Ada.Strings.Fixed.Index
        (Improve.Refinement.Model_Runner_Runtime.Name (Runtime), Digest) > 0,
      "runtime identity was not bound to the model digest");
   declare
      Identity : constant Improve.Refinement.Adapter_Provenance :=
        Improve.Refinement.Model_Runner_Runtime.Details (Runtime);
   begin
      Check
        (Length (Identity.Canonical_Path) > 0 and then Length (Identity.Architecture) > 0 and then
         Identity.Model_Bytes > 0 and then Identity.Model_Parts > 0 and then
         To_String (Identity.Model_SHA256) = Digest,
         "runtime did not expose complete model diagnostics");
   end;

   declare
      Result : constant Improve.Refinement.Refinement_Result := Run_Refinement;
   begin
      Check
        (Result.Status = Improve.Refinement.Refined,
         "real inference did not validate: "
         & Improve.Refinement.Refinement_Status'Image (Result.Status)
         & ": " & To_String (Result.Diagnostic));
      Check
        (Result.Plan.Fingerprint /= Draft.Fingerprint,
         "validated inference did not replace the draft fingerprint");
      Check
        (Ada.Strings.Fixed.Index
           (To_String (Result.Plan.Planner_Id), Digest) > 0,
         "validated plan provenance did not retain the model digest");
      Check
        (Result.Plan.Agent_Model_SHA256 = To_Unbounded_String (Digest)
         and then Length (Result.Plan.Agent_Provider_Id) > 0,
         "validated plan did not retain typed model provenance");
      Check
        (Seen.Generations > 0,
         "runtime did not forward generation progress");

      declare
         Context : constant Improve.Refinement.Planning_Context :=
           Improve.Refinement.Build_Context (Draft, (others => <>));
         Response : Improve.Refinement.Agent_Response;
      begin
         Improve.Refinement.Model_Runner_Runtime.Infer
           (Runtime, "wrong-model", Context, Improve.Refinement.Response_Schema,
            1, 1_024, Response);
         Check
           (Response.Status = Improve.Refinement.Agent_Unavailable
            and then To_String (Response.Diagnostic) = "model_identity_mismatch",
            "runtime accepted a mismatched caller model identity");
      end;

      declare
         Small : Improve.Refinement.Limits := (others => <>);
      begin
         Small.Maximum_Response_Bytes := 32;
         declare Bounded : constant Improve.Refinement.Refinement_Result := Run_Refinement (Small); begin
            Check
              (Bounded.Status = Improve.Refinement.Malformed_Fallback
               and then Ada.Strings.Fixed.Index
                 (To_String (Bounded.Diagnostic), "output_limit") > 0,
               "runtime output bound did not reach the adapter fallback");
         end;
      end;

      Improve.Refinement.Model_Runner_Runtime.Configure_Completion
        (Runtime, Observer => Slow'Unchecked_Access);
      declare
         Timed : Improve.Refinement.Limits := (others => <>);
      begin
         Timed.Timeout_Seconds := 1;
         declare Expired : constant Improve.Refinement.Refinement_Result := Run_Refinement (Timed); begin
            Check
              (Expired.Status = Improve.Refinement.Timeout_Fallback,
               "runtime deadline did not reach the timeout fallback");
         end;
      end;
      Improve.Refinement.Model_Runner_Runtime.Configure_Completion
        (Runtime, Observer => Seen'Unchecked_Access);

      Tiny_Model.Write
        (Exhausted_Path,
         Room                => 8_192,
         Forced_Output       => Answer (Draft.Tasks.First_Element),
         Forced_Output_Parts => 8);
      Improve.Refinement.Model_Runner_Runtime.Open
        (Runtime, Model_Id, Exhausted_Path,
         (Context_Tokens => 4_096, others => <>), Status);
      Check (Model_Runner.Errors.Is_Ok (Status), "bounded-context model did not reopen");
      declare Exhausted : constant Improve.Refinement.Refinement_Result := Run_Refinement; begin
         Check
           (Exhausted.Status = Improve.Refinement.Malformed_Fallback
            and then Ada.Strings.Fixed.Index
              (To_String (Exhausted.Diagnostic), "CONTEXT_FULL") > 0,
            "runtime context exhaustion was not distinguished: "
            & Improve.Refinement.Refinement_Status'Image (Exhausted.Status)
            & ": " & To_String (Exhausted.Diagnostic));
      end;

      Improve.Refinement.Model_Runner_Runtime.Open
        (Runtime, Model_Id, Model_Path, Options, Status);
      Check (Model_Runner.Errors.Is_Ok (Status), "runtime model did not reopen after context exhaustion");
      Token.Request;
      Improve.Refinement.Model_Runner_Runtime.Configure_Completion
        (Runtime,
         Cancel   => Token'Unchecked_Access,
         Observer => Seen'Unchecked_Access);
      declare
         Interrupted : Boolean := False;
         Context : constant Improve.Refinement.Planning_Context :=
           Improve.Refinement.Build_Context (Draft, (others => <>));
         Response : Improve.Refinement.Agent_Response;
      begin
         begin
            Improve.Refinement.Model_Runner_Runtime.Infer
              (Runtime, Model_Id, Context, Improve.Refinement.Response_Schema,
               1, 1_024, Response);
         exception
            when Improve.Cancelled_Error => Interrupted := True;
         end;
         Check
           (Interrupted,
            "runtime cancellation did not abort refinement");
      end;
      Token.Reset;
      Improve.Refinement.Model_Runner_Runtime.Configure_Completion
        (Runtime, Observer => Seen'Unchecked_Access);

      declare
         First_Digest : constant String := Digest;
         First_Planner : constant Unbounded_String := Result.Plan.Planner_Id;
         First_Fingerprint : constant Unbounded_String := Result.Plan.Fingerprint;
      begin
         Tiny_Model.Write
           (Variant_Path,
            Room                => 8_193,
            Forced_Output       => Answer (Draft.Tasks.First_Element),
            Forced_Output_Parts => 2);
         Improve.Refinement.Model_Runner_Runtime.Open
           (Runtime, Model_Id, Variant_Path, Options, Status);
         Check (Model_Runner.Errors.Is_Ok (Status), "variant runtime model did not open");
         declare
            Variant_Digest : constant String :=
              Improve.Refinement.Model_Runner_Runtime.Model_SHA256 (Runtime);
            Variant : constant Improve.Refinement.Refinement_Result := Run_Refinement;
         begin
            Check
              (Variant.Status = Improve.Refinement.Refined
               and then Variant_Digest /= First_Digest
               and then Variant.Plan.Agent_Model_SHA256 = To_Unbounded_String (Variant_Digest)
               and then Variant.Plan.Planner_Id /= First_Planner
               and then Variant.Plan.Fingerprint /= First_Fingerprint,
               "reopened model did not replace digest-bound plan provenance");
         end;
      end;
   end;

   declare
      Valid : constant String := Answer (Draft.Tasks.First_Element);
      Marker : constant String := """confidence"":90";
      Position : constant Natural := Ada.Strings.Fixed.Index (Valid, Marker);
      Invalid : constant String :=
        Valid (Valid'First .. Position - 1) & """confidence"":101"
        & Valid (Position + Marker'Length .. Valid'Last);
   begin
      Check (Position > 0, "malformed-response fixture could not locate confidence");
      Tiny_Model.Write
        (Malformed_Path, Room => 8_192, Forced_Output => Invalid);
      Improve.Refinement.Model_Runner_Runtime.Open
        (Runtime, Model_Id, Malformed_Path, Options, Status);
      Check (Model_Runner.Errors.Is_Ok (Status), "malformed-response model did not open");
      declare Malformed : constant Improve.Refinement.Refinement_Result := Run_Refinement; begin
         Check
           (Malformed.Status = Improve.Refinement.Malformed_Fallback,
            "strict response decoding accepted an unexpected generated field");
      end;
   end;

   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime, Model_Id, Root & "/missing.gguf", Options, Status);
   Check
     (Model_Runner.Errors.Is_Error (Status)
      and then not Improve.Refinement.Model_Runner_Runtime.Is_Open (Runtime)
      and then Improve.Refinement.Model_Runner_Runtime.Model_SHA256 (Runtime) = [1 .. 64 => '0'],
      "failed reopen retained stale model state or provenance");

   Copy_Model
     (Model_Path, Corrupt_Path, Maximum => 4,
      Replace_Old => "GGUF", Replace_New => "NOPE");
   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime, Model_Id, Corrupt_Path, Options, Status);
   Check
     (Status.Code = Model_Runner.Errors.GGUF_Invalid_Magic,
      "corrupt GGUF did not produce the stable invalid-magic diagnostic");

   Copy_Model (Model_Path, Truncated_Path, Maximum => 24);
   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime, Model_Id, Truncated_Path, Options, Status);
   Check
     (Status.Code = Model_Runner.Errors.GGUF_Truncated,
      "truncated GGUF did not produce the stable truncation diagnostic");

   Copy_Model
     (Model_Path, Unsupported_Path,
      Replace_Old => "llama", Replace_New => "zzzzz");
   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime, Model_Id, Unsupported_Path, Options, Status);
   Check
     (Status.Code = Model_Runner.Errors.Arch_Unsupported,
      "unsupported GGUF architecture did not produce the stable architecture diagnostic");

   declare
      Truncations : constant array (Positive range <>) of Positive := [1, 2, 3, 8, 16, 32, 64, 128];
   begin
      for Keep of Truncations loop
         Copy_Model (Model_Path, Fuzz_Path, Maximum => Keep);
         Improve.Refinement.Model_Runner_Runtime.Open
           (Runtime, Model_Id, Fuzz_Path, Options, Status);
         Check
           (Model_Runner.Errors.Is_Error (Status),
            "truncation corpus unexpectedly opened at byte" & Positive'Image (Keep));
      end loop;
   end;

   declare
      Corpus : Improve.Model.UString_Vectors.Vector;
      Response : Improve.Refinement.Agent_Response;
   begin
      Corpus.Append (To_Unbounded_String (""));
      Corpus.Append (To_Unbounded_String ("null"));
      Corpus.Append (To_Unbounded_String ("[]"));
      Corpus.Append (To_Unbounded_String ("{}"));
      Corpus.Append (To_Unbounded_String ("{""proposals"":null}"));
      Corpus.Append (To_Unbounded_String ("{""proposals"":[{}]}"));
      Corpus.Append (To_Unbounded_String ("{""proposals"":[]}" & ASCII.NUL));
      Corpus.Append (To_Unbounded_String (String'([1 .. 4_097 => 'x'])));
      for Value of Corpus loop
         Improve.Refinement.Codec.Decode_Response (To_String (Value), 4_096, Response);
         Check
           (Response.Status = Improve.Refinement.Malformed_Response,
            "constrained-JSON fuzz corpus produced a ready proposal");
      end loop;
   end;

   Check_Format ("qwen2-f16", Tiny_Model.F16, Tiny_Model.Qwen2);
   Check_Format ("gemma-q8", Tiny_Model.Q8_0, Tiny_Model.Gemma);
   Check_Format ("llama-q4k", Tiny_Model.Q4_K, Tiny_Model.Llama);

   Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
   Check
     (Improve.Refinement.Model_Runner_Runtime.Model_SHA256 (Runtime) =
        [1 .. 64 => '0'],
      "closed runtime retained its model digest");
   Ada.Directories.Delete_Tree (Root);
exception
   when others =>
      Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Delete_Tree (Root);
      end if;
      raise;
end Runtime_End_To_End;
