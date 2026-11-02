--  Command metadata shared by strict parsing, help, and phased dispatch.
package Improve.Commands is
   function Implementation_Phase (Name : String) return Natural;
   --  Return the first implementation phase that owns a command, or zero for help and version.
end Improve.Commands;

