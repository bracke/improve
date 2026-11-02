package body Improve.Model is
   function Image (Item : Candidate_Kind) return String is
     (case Item is
         when Remediation_Candidate => "remediation",
         when Investigation_Candidate => "investigation",
         when Diagnostic_Candidate => "diagnostic");

   function Image (Item : Priority) return String is
     (case Item is
         when Critical_Priority => "critical",
         when High_Priority => "high",
         when Normal_Priority => "normal",
         when Low_Priority => "low");
end Improve.Model;

