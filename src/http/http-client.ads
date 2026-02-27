--  HTTP client thin bindings over libcurl.
--  Used by all LLM providers and tool-web-fetch for outbound HTTP calls.
--  Security note: every outbound call is policy-checked by the caller via
--  Security.Policy before this package is invoked.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

pragma SPARK_Mode (Off);
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

   --  SSRF protection: returns False if URL targets loopback, link-local,
   --  private RFC-1918 ranges, or cloud metadata endpoints.
   --  Call this before any outbound HTTP request to untrusted URLs.
   function Is_Safe_URL (URL : String) return Boolean;

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

   --  Callback type for streaming responses.
   type Stream_Proc_Access is access procedure (Chunk : String);

   --  Like Post_JSON but streams SSE lines to On_Chunk as they arrive.
   --  Response body is not buffered; On_Chunk is called per complete line.
   --  The HTTP status code is still returned in the Response record.
   function Post_JSON_Streaming
     (URL        : String;
      Headers    : Header_Array;
      Body_JSON  : String;
      On_Chunk   : Stream_Proc_Access;
      Timeout_Ms : Natural := 0) return Response;

end HTTP.Client;
