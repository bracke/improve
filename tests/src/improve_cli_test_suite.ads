with AUnit.Test_Suites;

--  Parser and process-boundary tests kept separate from domain integration fixtures.
package Improve_CLI_Test_Suite is
   function Suite return AUnit.Test_Suites.Access_Test_Suite;
end Improve_CLI_Test_Suite;
