pragma SPARK_Mode (Off);
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Tools.Browser is

   type Browse_Result is record
      Success  : Boolean := False;
      Text     : Unbounded_String;   -- page text content
      Title    : Unbounded_String;   -- page title
      Error    : Unbounded_String;
   end record;

   type Screenshot_Result is record
      Success    : Boolean := False;
      PNG_Base64 : Unbounded_String; -- base64-encoded PNG
      Title      : Unbounded_String;
      Error      : Unbounded_String;
   end record;

   Bridge_URL : Unbounded_String;  -- set from config at startup

   --  Fetch page text via browser-bridge.
   function Browse (URL : String; Timeout_Ms : Positive := 15_000)
     return Browse_Result;

   --  Take a screenshot via browser-bridge.
   function Screenshot (URL : String; Timeout_Ms : Positive := 15_000)
     return Screenshot_Result;

end Tools.Browser;
