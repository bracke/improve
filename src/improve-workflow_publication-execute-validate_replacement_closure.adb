separate (Improve.Workflow_Publication.Execute)
procedure Validate_Replacement_Closure is
   Replaced : String_Index_Maps.Map;
   Memo     : String_Index_Maps.Map;
   Visiting : String_Index_Maps.Map;

   function Depends_On_Replaced (Spec : Improve.Model.Task_Specification) return Boolean is
      Identity : constant String := To_String (Spec.Id);
      Result   : Boolean := False;
   begin
      if Memo.Contains (Identity) then
         return Memo.Element (Identity) = 2;
      elsif Visiting.Contains (Identity) then
         raise Data_Error with "task dependency graph contains a cycle at " & Identity;
      end if;
      Visiting.Insert (Identity, 1);
      for Dependency of Spec.Dependencies loop
         declare
            Target : constant String := To_String (Dependency);
         begin
            if Replaced.Contains (Target) then
               Result := True;
            elsif Plan_Indexes.Contains (Target) then
               Result := Depends_On_Replaced (Plan.Tasks (Plan_Indexes.Element (Target)));
            else
               raise Data_Error with "unknown persisted task dependency " & Target;
            end if;
            exit when Result;
         end;
      end loop;
      Visiting.Delete (Identity);
      Memo.Insert (Identity, (if Result then 2 else 1));
      return Result;
   end Depends_On_Replaced;
begin
   for Spec of Selected loop
      if not Has_Current_Mapping (Spec) and then not Predecessors_Of (Spec).Is_Empty then
         Replaced.Insert (To_String (Spec.Id), 1);
      end if;
   end loop;
   if Replaced.Is_Empty then
      return;
   end if;
   for Spec of Plan.Tasks loop
      if not Is_Selected (Spec.Id) and then not Has_Current_Mapping (Spec) and then
        Depends_On_Replaced (Spec)
      then
         for Mapping of Existing loop
            if Is_Predecessor (Mapping, Spec) then
               declare
                  Definition   : Records.Item;
                  Native_State : constant String := Tasks.State_Of
                    (Store, To_String (Mapping.Harness_Task_Id));
                  Core_State   : constant String := Tasks.Counts_As (Store, Native_State);
               begin
                  Tasks.Definition (Store, To_String (Mapping.Harness_Task_Id), Definition, Status);
                  Require_Ok (Status, "read downstream native task " & To_String (Mapping.Harness_Task_Id));
                  if Records.Get (Definition, "created_by") /= "improve" or else
                    Records.Get (Definition, "origin") /= To_String (Mapping.Origin)
                  then
                     raise Data_Error with "downstream native task has invalid Improve provenance";
                  elsif Core_State not in "complete" | "cancelled" | "rejected" then
                     raise Data_Error with
                       "selective replacement would strand published dependent " & To_String (Spec.Id) &
                       " (" & To_String (Mapping.Harness_Task_Id) & " is " & Native_State &
                       "); publish the complete plan so its dependency can be replaced atomically";
                  end if;
               end;
            end if;
         end loop;
      end if;
   end loop;
end Validate_Replacement_Closure;
