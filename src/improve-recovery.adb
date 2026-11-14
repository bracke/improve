package body Improve.Recovery is
   function Recover
     (State_Path      : String;
      Quality_Path    : String;
      Requested_Kind : String;
      Maximum         : Positive;
      Limits          : Improve.Storage.Read_Limits := Improve.Storage.Default_Read_Limits;
      Quality_Limits  : Ada_Quality.Reporting.Load_Limits := (others => <>);
      Evidence_Limits : Improve.Config.Evidence_Limits := Improve.Config.Default_Evidence_Limits)
      return Recovery_Report is
     (Improve.Operations.Recovery.Run
        (State_Path, Quality_Path, Requested_Kind, Maximum, Limits, Quality_Limits, Evidence_Limits));
end Improve.Recovery;
