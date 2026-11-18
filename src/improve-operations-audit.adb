with Ada.Strings.Unbounded;
with Improve.Model;

package body Improve.Operations.Audit is
   use Ada.Strings.Unbounded;

   function Run
     (State_Path : String;
      Plan_Id    : String;
      Revision   : Natural := 0;
      Maximum    : Positive := Improve.Storage.Default_Query_Maximum;
      Limits     : Improve.Storage.Persistence_Limits := Improve.Storage.Default_Persistence_Limits)
      return Improve.Results.Audit_Bundle is
      Store : Improve.Storage.Store;
   begin
      Improve.Storage.Open (Store, State_Path, Writable => False, Limits => Limits);
      declare
         Plan : constant Improve.Model.Plan_Revision :=
           (if Revision = 0 then Improve.Storage.Load (Store, Plan_Id, Limits)
            else Improve.Storage.Load (Store, Plan_Id, Positive (Revision), Limits));
         Result : constant Improve.Results.Audit_Bundle :=
           (Plan     => Plan,
            Approved => Improve.Storage.Is_Approved
              (Store, To_String (Plan.Plan_Id), Plan.Revision, Limits),
            History  => Improve.Storage.History
              (Store, To_String (Plan.Plan_Id), Plan.Revision, Maximum, Limits));
      begin
         Improve.Storage.Close (Store);
         return Result;
      end;
   end Run;
end Improve.Operations.Audit;
