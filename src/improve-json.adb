with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada_Quality.Types;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Improve.JSON is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;

   LF : constant Character := Character'Val (10);

   function Lower (Text : String) return String is (Ada.Characters.Handling.To_Lower (Text));

   function Projects
     (Values      : Ada_Quality.Reporting.Project_Vectors.Vector;
      Snapshot_Id : String) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("projects"));
      Doc.Insert (Data, "snapshot", Doc.New_String (Snapshot_Id));
      for Value of Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "id", Doc.New_Integer (Long_Long_Integer (Value.Id)));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Value.Path)));
            Doc.Insert (Item, "enabled", Doc.New_Boolean (Value.Enabled));
            Doc.Insert (Item, "removed", Doc.New_Boolean (Value.Removed));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "projects", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Projects;

   function Findings
     (Selected : Improve.Source.Selection;
      Values   : Improve.Model.Finding_Vectors.Vector) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Data : constant Node := Doc.New_Object;
      List : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (JSON_Format_Version));
      Doc.Insert (Root, "command", Doc.New_String ("findings"));
      Doc.Insert (Data, "project_id", Doc.New_Integer (Long_Long_Integer (Selected.Project.Id)));
      Doc.Insert (Data, "project", Doc.New_String (To_String (Selected.Project.Name)));
      Doc.Insert (Data, "run_id", Doc.New_Integer (Long_Long_Integer (Selected.Assessment.Run.Id)));
      Doc.Insert (Data, "snapshot", Doc.New_String (To_String (Selected.Baseline.Snapshot_Id)));
      for Value of Values loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "indicator", Doc.New_String (Ada_Quality.Types.Image (Value.Indicator)));
            Doc.Insert (Item, "rule", Doc.New_String (To_String (Value.Rule)));
            Doc.Insert
              (Item, "severity", Doc.New_String (Lower (Ada_Quality.Types.Severity'Image (Value.Level))));
            Doc.Insert (Item, "path", Doc.New_String (To_String (Value.Relative_Path)));
            Doc.Insert (Item, "line", Doc.New_Integer (Long_Long_Integer (Value.Line)));
            Doc.Insert (Item, "fingerprint", Doc.New_String (To_String (Value.Fingerprint)));
            Doc.Insert (Item, "subject", Doc.New_String (To_String (Value.Semantic_Subject)));
            Doc.Insert (Item, "message", Doc.New_String (To_String (Value.Message)));
            Doc.Insert (Item, "evidence", Doc.New_String (To_String (Value.Evidence)));
            Doc.Insert (Item, "candidate_kind", Doc.New_String (Improve.Model.Image (Value.Kind)));
            Doc.Insert (Item, "indicator_level", Doc.New_Boolean (Value.Indicator_Level));
            Doc.Append (List, Item);
         end;
      end loop;
      Doc.Insert (Data, "findings", List);
      Doc.Insert (Root, "data", Data);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc) & LF;
   end Findings;
end Improve.JSON;

