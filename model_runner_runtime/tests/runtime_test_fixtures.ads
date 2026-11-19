--  Shared Ada Quality fixture construction for runtime integration tests.
package Runtime_Test_Fixtures is
   procedure Build_Quality_Fixture
     (Database : String;
      Target   : String;
      Project  : out Positive);
end Runtime_Test_Fixtures;
