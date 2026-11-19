with Model_Runner.Errors;

with Improve.Refinement.Model_Runner_Runtime;

procedure Runtime_Schema_Smoke is
   use type Model_Runner.Errors.Error_Domain;

   Runtime : Improve.Refinement.Model_Runner_Runtime.Runtime;
   Status  : Model_Runner.Errors.Error_Info;
begin
   Improve.Refinement.Model_Runner_Runtime.Open
     (Runtime,
      Model => "schema-smoke",
      Path => "model_runner_runtime/tests/this-model-must-not-exist.gguf",
      Status => Status);

   if Model_Runner.Errors.Is_Ok (Status) then
      raise Program_Error with "missing smoke model unexpectedly opened";
   elsif Model_Runner.Errors.Domain (Status.Code) = Model_Runner.Errors.Domain_Grammar then
      raise Program_Error with "Improve response schema was rejected";
   end if;

   Improve.Refinement.Model_Runner_Runtime.Close (Runtime);
   if Improve.Refinement.Model_Runner_Runtime.Is_Open (Runtime) then
      raise Program_Error with "closed runtime remained open";
   end if;
end Runtime_Schema_Smoke;
