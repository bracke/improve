--  Resolve a stable task identity from the previous revision index.
separate (Improve.Storage)
function Previous_Task_Id
  (Spec           : Improve.Model.Task_Specification;
   Findings       : Improve.Model.Finding_Vectors.Vector;
   Previous_Tasks : String_Value_Maps.Map) return Unbounded_String is
   Key : constant String :=
     Task_Identity_Key
       (To_String (Spec.Category), To_String (Spec.Title), To_String (Spec.Acceptance),
        Stable_Digest (Pack (Spec.Finding_Keys)));
begin
   if Previous_Tasks.Contains (Key) then
      return Previous_Tasks.Element (Key);
   end if;
   declare
      Legacy : Improve.Model.UString_Vectors.Vector;
   begin
      for Link of Spec.Finding_Keys loop
         declare
            Matched : Boolean := False;
         begin
            for Finding of Findings loop
               if To_String (Link) = Improve.Model.Finding_Key (Finding) then
                  Legacy.Append (Finding.Fingerprint);
                  Matched := True;
                  exit;
               end if;
            end loop;
            if not Matched then
               Legacy.Append (Link);
            end if;
         end;
      end loop;
      declare
         Legacy_Key : constant String :=
           Task_Identity_Key
             (To_String (Spec.Category), To_String (Spec.Title), To_String (Spec.Acceptance),
              Stable_Digest (Pack (Legacy)));
      begin
         return
           (if Previous_Tasks.Contains (Legacy_Key) then Previous_Tasks.Element (Legacy_Key)
            else Null_Unbounded_String);
      end;
   end;
end Previous_Task_Id;
