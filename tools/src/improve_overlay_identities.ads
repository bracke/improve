--  Validation for auditable dependency-overlay identities.
package Improve_Overlay_Identities is
   --  Return whether Value is `dependency@commit` entries separated by commas.
   function Valid (Value : String; Allow_None : Boolean := True) return Boolean;
end Improve_Overlay_Identities;
