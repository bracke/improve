with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Improve.Config;
with Improve.Model;
with Improve.Source;

--  Independent comparison of remediation intent with completed measurements.
package Improve.Verification is
   type Task_Result is record
      Task_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Outcome     : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Matched     : Natural := 0;
      Total       : Natural := 0;
      Explanation : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Result_Vectors is new Ada.Containers.Vectors (Positive, Task_Result);

   type Report is record
      Plan_Id          : Ada.Strings.Unbounded.Unbounded_String;
      Baseline_Run     : Positive;
      Verification_Run : Positive;
      Outcome          : Improve.Model.Quality_Outcome := Improve.Model.Unverified;
      Comparable       : Boolean := False;
      New_Critical     : Natural := 0;
      Explanation      : Ada.Strings.Unbounded.Unbounded_String;
      Tasks            : Result_Vectors.Vector;
   end record;

   function Evaluate
     (Plan     : Improve.Model.Plan_Revision;
      Current  : Improve.Source.Selection;
      Settings : Improve.Config.Settings;
      Task_Id  : String := "";
      Previously_Verified : Improve.Model.UString_Vectors.Vector :=
        Improve.Model.UString_Vectors.Empty_Vector) return Report;
   --  Evaluate existing completed evidence without running a measurement.
end Improve.Verification;
