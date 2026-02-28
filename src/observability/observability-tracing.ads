pragma SPARK_Mode (Off);
package Observability.Tracing is
   procedure Initialize (OTLP_Endpoint : String);
   --  Call once at startup; no-ops all tracing if empty string

   function Is_Enabled return Boolean;

   type Span_ID is private;
   No_Span : constant Span_ID;

   function Start_Span (Name : String; Parent : Span_ID := No_Span) return Span_ID;
   procedure End_Span (S : Span_ID);
   procedure Set_Attribute (S : Span_ID; Key : String; Value : String);
   procedure Set_Attribute (S : Span_ID; Key : String; Value : Integer);
   procedure Set_Error (S : Span_ID; Message : String);

private
   type Span_ID is new Natural;
   No_Span : constant Span_ID := 0;
end Observability.Tracing;
