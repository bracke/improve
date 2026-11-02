package body Improve.Commands is
   function Implementation_Phase (Name : String) return Natural is
     (if Name in "help" | "version" then 0
      elsif Name = "config" then 1
      elsif Name in "projects" | "findings" then 2
      elsif Name = "plan" then 3
      elsif Name in "apply" | "tasks" then 5
      elsif Name in "status" | "refresh" | "verify" | "recover" then 6
      else Natural'Last);
end Improve.Commands;

