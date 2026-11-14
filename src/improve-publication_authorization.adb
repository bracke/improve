with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Improve.Operations;
with Improve.Source;

package body Improve.Publication_Authorization is
   use Ada.Strings.Unbounded;

   function Number (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   procedure Validate
     (Plan           : Improve.Model.Plan_Revision;
      State_Path     : String;
      Quality_Path      : String;
      Quality_Limits    : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Quality_Database_Bytes : Positive := 1_073_741_824;
      Maximum_Assessment_Bytes : Positive := 16_777_216;
      Retain_On_Failure : Boolean := False) is
      Quality : Improve.Source.Repository;

      procedure Reject (Message : String) is
      begin
         raise Data_Error with
           Message & (if Retain_On_Failure then "; operation retained without creating native tasks" else "");
      end Reject;
   begin
      if Improve.Source.Working_Fingerprint (To_String (Plan.Project.Path), State_Path) /=
        To_String (Plan.Working_Source_Id)
      then
         Reject ("current project source differs from the assessment baseline; remeasure and refresh the plan");
      end if;
      Improve.Source.Open (Quality, Quality_Path, Quality_Limits, Maximum_Quality_Database_Bytes);
      declare
         Project : constant Improve.Model.Project_Reference :=
           Improve.Source.Resolve_Project (Quality, Number (Plan.Project.Id));
         Baseline : Improve.Source.Selection;
         Latest : constant Improve.Source.Selection :=
           Improve.Source.Select_Assessment (Quality, Project, Maximum_Bytes => Maximum_Assessment_Bytes);
      begin
         Improve.Operations.Require_Project_Identity (Plan.Project, Project);
         Baseline := Improve.Source.Select_Assessment
           (Quality, Project, Plan.Baseline.Run_Id, Maximum_Assessment_Bytes);
         if Baseline.Baseline.Project_Id /= Plan.Baseline.Project_Id or else
           Baseline.Baseline.Source_Id /= Plan.Baseline.Source_Id or else
           Baseline.Baseline.Policy_Id /= Plan.Baseline.Policy_Id or else
           Baseline.Baseline.Toolchain_Id /= Plan.Baseline.Toolchain_Id or else
           Baseline.Baseline.Evidence_Id /= Plan.Baseline.Evidence_Id
         then
            Reject ("stored quality assessment no longer matches the plan baseline");
         end if;
         if Latest.Baseline.Run_Id > Plan.Baseline.Run_Id and then
           Latest.Baseline.Source_Id /= Plan.Baseline.Source_Id
         then
            Reject ("project source changed after planning; refresh the plan before publication");
         elsif Latest.Baseline.Run_Id > Plan.Baseline.Run_Id and then
           Latest.Baseline.Policy_Id /= Plan.Baseline.Policy_Id
         then
            Reject
              ("quality policy changed after planning; replan before publication to preserve acceptance intent");
         end if;
      end;
      Improve.Source.Close (Quality);
   exception
      when others =>
         Improve.Source.Close (Quality);
         raise;
   end Validate;
end Improve.Publication_Authorization;
