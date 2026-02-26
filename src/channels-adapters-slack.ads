with Channels.Adapters;
with Channels.Security;

package Channels.Adapters.Slack with SPARK_Mode is
   subtype Security_Context is Channels.Adapters.Security_Context;
   subtype Inbound_Decision is Channels.Adapters.Inbound_Decision;
   subtype Inbound_Result is Channels.Adapters.Inbound_Result;
   subtype Outbound_Decision is Channels.Adapters.Outbound_Decision;
   subtype Outbound_Result is Channels.Adapters.Outbound_Result;

   function Inbound_Acceptance
     (Channel_Enabled : Boolean;
      Context         : Security_Context) return Inbound_Result is
      (Channels.Adapters.Inbound_Acceptance
         (Channel         => Channels.Security.Slack_Channel,
          Channel_Enabled => Channel_Enabled,
          Context         => Context));

   function Inbound_Acceptance
     (Context : Security_Context) return Inbound_Result is
      (Inbound_Acceptance (Channel_Enabled => True, Context => Context));

   function Outbound_Eligibility
     (Channel_Enabled : Boolean;
      Context         : Security_Context) return Outbound_Result is
     (Channels.Adapters.Outbound_Eligibility
        (Channel         => Channels.Security.Slack_Channel,
         Channel_Enabled => Channel_Enabled,
         Context         => Context));
end Channels.Adapters.Slack;
