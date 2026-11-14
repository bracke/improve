package body Improve.Recovery is
   function Recover
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Maximum_Quality_Database_Bytes : Positive := 1_073_741_824;
      Maximum_Assessment_Bytes : Positive := 16_777_216)
      return Recovery_Report is
     (Improve.Operations.Recovery.Run
        (State_Path, Quality_Path, Requested_Kind, Maximum, Limits, Quality_Limits,
         Maximum_Quality_Database_Bytes, Maximum_Assessment_Bytes));
end Improve.Recovery;
