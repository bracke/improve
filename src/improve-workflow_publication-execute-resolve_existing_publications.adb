separate (Improve.Workflow_Publication.Execute)
procedure Resolve_Existing_Publications (Kind : String) is
begin
   for Spec of Selected loop
      declare
         Contract     : constant Unbounded_String :=
           To_Unbounded_String (Contract_Of (Spec.Id));
         Origin       : Unbounded_String := To_Unbounded_String
           (Origin_Of (Plan, Spec, To_String (Contract), Publication_Namespace));
         Harness_Id   : Unbounded_String;
         Was_Mapped   : Boolean := False;
         Predecessors : constant Improve.Model.UString_Vectors.Vector := Predecessors_Of (Spec);
      begin
         for Index of Predecessor_Indexes_Of (Spec) loop
            declare
               Target : constant String := Retirement_Target (Existing (Index));
               pragma Unreferenced (Target);
            begin
               null;
            end;
         end loop;
         if Current_Mappings.Contains (To_String (Spec.Id)) then
            declare
               Mapping : Improve.State.Publication_Record renames
                 Existing (Current_Mappings.Element (To_String (Spec.Id)));
            begin
               declare
                  Definition : Records.Item;
               begin
                  Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
                  Require_Ok (Status, "read previously published harness task " & To_String (Spec.Id));
                  if Mapping.Origin /= Origin and then
                    To_String (Mapping.Origin) /= Legacy_Origin_Of (Plan, Spec, To_String (Contract))
                  then
                     raise Data_Error with "stored publication mapping has an incompatible stable origin";
                  end if;
                  Require_Compatible_Definition
                    (Definition, Spec, Kind, To_String (Mapping.Origin), To_String (Contract), Predecessors);
               end;
               Origin := Mapping.Origin;
               Harness_Id := Mapping.Harness_Task_Id;
               Was_Mapped := True;
            end;
         end if;
         if not Was_Mapped then
            Harness_Id := To_Unbounded_String
              (Existing_By_Origin (To_String (Origin), Spec, Kind, To_String (Contract), Predecessors));
         end if;
         Result.Tasks.Append
           (Published_Task'
              (Improve_Id => Spec.Id,
               Harness_Id => Harness_Id,
               Origin     => Origin,
               Contract   => Contract,
               State      => To_Unbounded_String
                 (if Length (Harness_Id) = 0 then (if Dry_Run then "candidate" else "")
                  else Tasks.State_Of (Store, To_String (Harness_Id))),
               Recovered  => Length (Harness_Id) > 0));
      end;
   end loop;
end Resolve_Existing_Publications;
