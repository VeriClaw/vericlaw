--  Metrics: in-memory Prometheus counter/gauge store.
--  Thread-safe via a protected object; renders text exposition format on demand.

package Metrics is

   --  Increment a counter. Name is the metric suffix (e.g. "requests_total").
   --  Label is an optional label value (e.g. "telegram" for the channel label).
   procedure Increment (Name : String; Label : String := "");

   --  Return all counters and the uptime gauge in Prometheus text format.
   function Render return String;

end Metrics;
