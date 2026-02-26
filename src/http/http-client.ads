--  HTTP client thin bindings over libcurl.
--  Used by all LLM providers and tool-web-fetch for outbound HTTP calls.
--  Security note: every outbound call is policy-checked by the caller via
--  Security.Policy before this package is invoked.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package HTTP.Client is

   --  Maximum response body accepted (4 MB) to prevent memory exhaustion.
   Max_Response_Bytes : constant := 4 * 1024 * 1024;

   type HTTP_Method is (GET, POST, PUT, DELETE, PATCH);

   type Header is record
      Name  : Unbounded_String;
      Value : Unbounded_String;
   end record;

   type Header_Array is array (Positive range <>) of Header;

   type Response is record
      Status_Code  : Natural := 0;
      Body_Text    : Unbounded_String;
      Error        : Unbounded_String;  -- non-empty on transport failure
   end record;

   function Is_Success (R : Response) return Boolean is
     (R.Status_Code in 200 .. 299 and then Length (R.Error) = 0);

   --  Perform an HTTP request.
   --  TLS verification is always enabled (no way to disable via this API).
   --  Timeout_Ms: 0 means use default (30 000 ms).
   function Request
     (Method     : HTTP_Method;
      URL        : String;
      Headers    : Header_Array;
      Body_Text  : String        := "";
      Timeout_Ms : Natural       := 0) return Response;

   --  Convenience wrappers.
   function Get
     (URL        : String;
      Headers    : Header_Array;
      Timeout_Ms : Natural := 0) return Response;

   function Post_JSON
     (URL        : String;
      Headers    : Header_Array;
      Body_JSON  : String;
      Timeout_Ms : Natural := 0) return Response;

end HTTP.Client;
