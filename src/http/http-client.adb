--  libcurl thin bindings for HTTP.Client.
--  Requires libcurl at link time (-lcurl in vericlaw.gpr).

with Interfaces.C;            use Interfaces.C;
with Interfaces.C.Strings;    use Interfaces.C.Strings;
with System;

package body HTTP.Client
  with SPARK_Mode => Off
is

   Default_Timeout_Ms : constant := 30_000;

   --  -----------------------------------------------------------------------
   --  Thin C bindings to libcurl
   --  -----------------------------------------------------------------------

   type CURL_Handle is new System.Address;
   Null_CURL : constant CURL_Handle :=
     CURL_Handle (System.Null_Address);

   type CURL_Code is new int;
   CURLE_OK                   : constant CURL_Code := 0;
   CURLE_OPERATION_TIMEDOUT   : constant CURL_Code := 28;

   type CURL_Option is new int;
   CURLOPT_URL            : constant CURL_Option := 10_002;
   CURLOPT_WRITEFUNCTION  : constant CURL_Option := 20_011;
   CURLOPT_WRITEDATA      : constant CURL_Option := 10_001;
   CURLOPT_HTTPHEADER     : constant CURL_Option := 10_023;
   CURLOPT_POSTFIELDS     : constant CURL_Option := 10_015;
   CURLOPT_POST           : constant CURL_Option := 47;
   CURLOPT_CUSTOMREQUEST  : constant CURL_Option := 10_036;
   CURLOPT_TIMEOUT_MS     : constant CURL_Option := 155;
   CURLOPT_SSL_VERIFYPEER : constant CURL_Option := 64;
   CURLOPT_SSL_VERIFYHOST : constant CURL_Option := 81;
   CURLOPT_FOLLOWLOCATION : constant CURL_Option := 52;
   CURLOPT_MAXREDIRS      : constant CURL_Option := 68;

   type CURL_Info is new int;
   CURLINFO_RESPONSE_CODE : constant CURL_Info := 2_097_154;

   type CURL_Slist is new System.Address;
   Null_Slist : constant CURL_Slist := CURL_Slist (System.Null_Address);

   --  Write callback type: returns bytes consumed (must equal Size*NMemb).
   type Write_Callback is access function
     (Ptr      : chars_ptr;
      Size     : size_t;
      NMemb    : size_t;
      UserData : System.Address) return size_t
   with Convention => C;

   function curl_easy_init return CURL_Handle
   with Import, Convention => C, External_Name => "curl_easy_init";

   procedure curl_easy_cleanup (Handle : CURL_Handle)
   with Import, Convention => C, External_Name => "curl_easy_cleanup";

   function curl_easy_setopt_ptr
     (Handle : CURL_Handle;
      Option : CURL_Option;
      Value  : System.Address) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_setopt";

   --  Separate binding for C string (char*) options: pass chars_ptr VALUE
   --  directly so curl receives the pointer, not the address of the pointer.
   function curl_easy_setopt_cstr
     (Handle : CURL_Handle;
      Option : CURL_Option;
      Value  : chars_ptr) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_setopt";

   function curl_easy_setopt_long
     (Handle : CURL_Handle;
      Option : CURL_Option;
      Value  : long) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_setopt";

   function curl_easy_setopt_fn
     (Handle : CURL_Handle;
      Option : CURL_Option;
      Value  : Write_Callback) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_setopt";

   function curl_easy_perform (Handle : CURL_Handle) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_perform";

   function curl_easy_getinfo_long
     (Handle : CURL_Handle;
      Info   : CURL_Info;
      Value  : access long) return CURL_Code
   with Import, Convention => C, External_Name => "curl_easy_getinfo";

   function curl_slist_append
     (List : CURL_Slist;
      Str  : chars_ptr) return CURL_Slist
   with Import, Convention => C, External_Name => "curl_slist_append";

   procedure curl_slist_free_all (List : CURL_Slist)
   with Import, Convention => C, External_Name => "curl_slist_free_all";

   --  -----------------------------------------------------------------------
   --  Streaming write callback state (package-level; CLI mode, not concurrent).
   --  -----------------------------------------------------------------------

   Streaming_Proc   : Stream_Proc_Access := null;
   Streaming_Buffer : Unbounded_String;

   --  -----------------------------------------------------------------------
   --  Write callback — accumulates response body into an Unbounded_String.
   --  -----------------------------------------------------------------------

   --  We use a global buffer pointer trick: store the access to the
   --  Unbounded_String in the UserData address passed to CURLOPT_WRITEDATA.
   function Write_CB
     (Ptr      : chars_ptr;
      Size     : size_t;
      NMemb    : size_t;
      UserData : System.Address) return size_t
   with Convention => C;

   function Write_CB
     (Ptr      : chars_ptr;
      Size     : size_t;
      NMemb    : size_t;
      UserData : System.Address) return size_t
   is
      Total   : constant size_t := Size * NMemb;
      Buffer  : Unbounded_String;
      for Buffer'Address use UserData;
      pragma Import (Ada, Buffer);
      Chunk   : constant String :=
        Value (Ptr, Total);
   begin
      if Length (Buffer) + Natural (Total) > Max_Response_Bytes then
         return 0;  -- Signal error to curl (CURLE_WRITE_ERROR)
      end if;
      Append (Buffer, Chunk);
      return Total;
   end Write_CB;

   --  -----------------------------------------------------------------------
   --  Streaming write callback — delivers complete SSE lines to Streaming_Proc.
   --  -----------------------------------------------------------------------

   function Write_CB_Streaming
     (Ptr      : chars_ptr;
      Size     : size_t;
      NMemb    : size_t;
      UserData : System.Address) return size_t
   with Convention => C;

   function Write_CB_Streaming
     (Ptr      : chars_ptr;
      Size     : size_t;
      NMemb    : size_t;
      UserData : System.Address) return size_t
   is
      pragma Unreferenced (UserData);
      Total : constant size_t := Size * NMemb;
      Chunk : constant String := Value (Ptr, Total);
      Found : Boolean;
   begin
      Append (Streaming_Buffer, Chunk);
      --  Extract and dispatch each complete newline-terminated line.
      loop
         Found := False;
         declare
            S : constant String := To_String (Streaming_Buffer);
         begin
            for I in S'Range loop
               if S (I) = ASCII.LF then
                  declare
                     Line_End : constant Natural :=
                       (if I > S'First and then S (I - 1) = ASCII.CR
                        then I - 2 else I - 1);
                     Line : constant String :=
                       (if Line_End >= S'First
                        then S (S'First .. Line_End) else "");
                  begin
                     if Streaming_Proc /= null then
                        Streaming_Proc (Line);
                     end if;
                  end;
                  Set_Unbounded_String (Streaming_Buffer, S (I + 1 .. S'Last));
                  Found := True;
                  exit;
               end if;
            end loop;
         end;
         exit when not Found;
      end loop;
      return Total;
   end Write_CB_Streaming;

   --  -----------------------------------------------------------------------
   --  SSRF protection
   --  -----------------------------------------------------------------------

   function Is_Safe_URL (URL : String) return Boolean is
      L : constant String := URL;

      function Has_Prefix (S, Prefix : String) return Boolean is
        (S'Length >= Prefix'Length
         and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

      --  Extract host from http(s)://host/...
      function Extract_Host return String is
         Start : Natural;
      begin
         if Has_Prefix (L, "http://") then
            Start := L'First + 7;
         elsif Has_Prefix (L, "https://") then
            Start := L'First + 8;
         else
            return "";
         end if;
         --  Host ends at '/', ':', or end of string.
         for I in Start .. L'Last loop
            if L (I) = '/' or else L (I) = ':' then
               return L (Start .. I - 1);
            end if;
         end loop;
         return L (Start .. L'Last);
      end Extract_Host;

      Host : constant String := Extract_Host;

      function Starts_With (S, Prefix : String) return Boolean is
        (S'Length >= Prefix'Length
         and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   begin
      --  Require http or https scheme.
      if not (Has_Prefix (L, "http://") or else Has_Prefix (L, "https://")) then
         return False;
      end if;

      --  Block loopback, localhost, link-local, private ranges.
      if Host = "localhost"
        or else Host = "::1"
        or else Starts_With (Host, "127.")
        or else Starts_With (Host, "169.254.")  --  link-local / cloud metadata
        or else Starts_With (Host, "10.")        --  RFC-1918
        or else Starts_With (Host, "192.168.")   --  RFC-1918
        or else Starts_With (Host, "0.")         --  this-network
        or else Starts_With (Host, "[::1]")      --  IPv6 loopback
        or else Starts_With (Host, "[fe80:")     --  IPv6 link-local
        or else Starts_With (Host, "[fc") or else Starts_With (Host, "[fd")  --  ULA
      then
         return False;
      end if;

      --  Block 172.16.0.0/12 (172.16.x.x – 172.31.x.x).
      if Starts_With (Host, "172.") and then Host'Length >= 7 then
         declare
            Second_Octet : constant String :=
              Host (Host'First + 4 .. Host'Last);
            Dot_Pos : Natural := 0;
         begin
            for I in Second_Octet'Range loop
               if Second_Octet (I) = '.' then
                  Dot_Pos := I;
                  exit;
               end if;
            end loop;
            if Dot_Pos > Second_Octet'First then
               declare
                  Oct : Natural := 0;
               begin
                  for I in Second_Octet'First .. Dot_Pos - 1 loop
                     if Second_Octet (I) in '0' .. '9' then
                        Oct := Oct * 10
                          + (Character'Pos (Second_Octet (I))
                             - Character'Pos ('0'));
                     end if;
                  end loop;
                  if Oct in 16 .. 31 then
                     return False;
                  end if;
               end;
            end if;
         end;
      end if;

      return True;
   end Is_Safe_URL;

   --  -----------------------------------------------------------------------
   --  Core implementation
   --  -----------------------------------------------------------------------

   function Request
     (Method     : HTTP_Method;
      URL        : String;
      Headers    : Header_Array;
      Body_Text  : String        := "";
      Timeout_Ms : Natural       := 0) return Response
   is
      Handle      : constant CURL_Handle := curl_easy_init;
      C_URL       : chars_ptr   := New_String (URL);
      Slist       : CURL_Slist  := Null_Slist;
      Code        : CURL_Code;
      HTTP_Code   : aliased long := 0;
      Effective_Timeout : constant long :=
        (if Timeout_Ms = 0 then long (Default_Timeout_Ms)
         else long (Timeout_Ms));

      Body_Buf    : Unbounded_String;
      Result      : Response;
      pragma Warnings (Off, Code);  --  curl_easy_setopt return values intentionally discarded
   begin
      --  SSRF guard: reject private/loopback URLs before any libcurl call.
      if not Is_Safe_URL (URL) then
         Set_Unbounded_String (Result.Error,
           "SSRF blocked: URL targets a private or reserved address");
         Free (C_URL);
         return Result;
      end if;

      if Handle = Null_CURL then
         Set_Unbounded_String (Result.Error, "curl_easy_init failed");
         Free (C_URL);
         return Result;
      end if;

      --  URL
      Code := curl_easy_setopt_cstr
        (Handle, CURLOPT_URL, C_URL);

      --  TLS: always verify
      Code := curl_easy_setopt_long
        (Handle, CURLOPT_SSL_VERIFYPEER, 1);
      Code := curl_easy_setopt_long
        (Handle, CURLOPT_SSL_VERIFYHOST, 2);

      --  Follow up to 5 redirects
      Code := curl_easy_setopt_long (Handle, CURLOPT_FOLLOWLOCATION, 1);
      Code := curl_easy_setopt_long (Handle, CURLOPT_MAXREDIRS, 5);

      --  Timeout
      Code := curl_easy_setopt_long
        (Handle, CURLOPT_TIMEOUT_MS, Effective_Timeout);

      --  Write callback
      Code := curl_easy_setopt_fn
        (Handle, CURLOPT_WRITEFUNCTION, Write_CB'Access);
      Code := curl_easy_setopt_ptr
        (Handle, CURLOPT_WRITEDATA, Body_Buf'Address);

      --  Build header slist
      for H of Headers loop
         declare
            Header_Str : constant String :=
              To_String (H.Name) & ": " & To_String (H.Value);
            C_H        : chars_ptr := New_String (Header_Str);
         begin
            Slist := curl_slist_append (Slist, C_H);
            Free (C_H);
         end;
      end loop;
      if Slist /= Null_Slist then
         Code := curl_easy_setopt_ptr
           (Handle, CURLOPT_HTTPHEADER, System.Address (Slist));
      end if;

      --  Method + body
      case Method is
         when POST =>
            Code := curl_easy_setopt_long (Handle, CURLOPT_POST, 1);
            if Body_Text'Length > 0 then
               declare
                  C_Body : chars_ptr := New_String (Body_Text);
               begin
                  Code := curl_easy_setopt_cstr
                    (Handle, CURLOPT_POSTFIELDS, C_Body);
                  --  Note: C_Body must outlive curl_easy_perform.
                  --  Using a stack-local here is safe because perform
                  --  is called before C_Body goes out of scope.
                  Code := curl_easy_perform (Handle);
                  Free (C_Body);
               end;
            else
               Code := curl_easy_perform (Handle);
            end if;
         when GET =>
            Code := curl_easy_perform (Handle);
         when others =>
            declare
               Method_Str : constant String := HTTP_Method'Image (Method);
               C_Method   : chars_ptr := New_String (Method_Str);
            begin
               Code := curl_easy_setopt_cstr
                 (Handle, CURLOPT_CUSTOMREQUEST, C_Method);
               if Body_Text'Length > 0 then
                  declare
                     C_Body : chars_ptr := New_String (Body_Text);
                  begin
                     Code := curl_easy_setopt_cstr
                       (Handle, CURLOPT_POSTFIELDS, C_Body);
                     Code := curl_easy_perform (Handle);
                     Free (C_Body);
                  end;
               else
                  Code := curl_easy_perform (Handle);
               end if;
               Free (C_Method);
            end;
      end case;

      if Code = CURLE_OPERATION_TIMEDOUT then
         Set_Unbounded_String
           (Result.Error,
            "Request timed out after" & long'Image (Effective_Timeout) & "ms");
      elsif Code /= CURLE_OK then
         Set_Unbounded_String
           (Result.Error, "curl_easy_perform error code:" & CURL_Code'Image (Code));
      else
         Code := curl_easy_getinfo_long
           (Handle, CURLINFO_RESPONSE_CODE, HTTP_Code'Access);
         Result.Status_Code := Natural (HTTP_Code);
         Result.Body_Text   := Body_Buf;
      end if;

      if Slist /= Null_Slist then
         curl_slist_free_all (Slist);
      end if;
      curl_easy_cleanup (Handle);
      Free (C_URL);
      return Result;
   end Request;

   function Get
     (URL        : String;
      Headers    : Header_Array;
      Timeout_Ms : Natural := 0) return Response is
   begin
      return Request (GET, URL, Headers, "", Timeout_Ms);
   end Get;

   function Post_JSON
     (URL        : String;
      Headers    : Header_Array;
      Body_JSON  : String;
      Timeout_Ms : Natural := 0) return Response
   is
      --  Prepend Content-Type header to caller-supplied headers.
      CT_Header : constant Header :=
        (Name  => To_Unbounded_String ("Content-Type"),
         Value => To_Unbounded_String ("application/json"));
      All_Headers : Header_Array (1 .. Headers'Length + 1);
   begin
      All_Headers (1) := CT_Header;
      All_Headers (2 .. All_Headers'Last) := Headers;
      return Request (POST, URL, All_Headers, Body_JSON, Timeout_Ms);
   end Post_JSON;

   function Post_JSON_Streaming
     (URL        : String;
      Headers    : Header_Array;
      Body_JSON  : String;
      On_Chunk   : Stream_Proc_Access;
      Timeout_Ms : Natural := 0) return Response
   is
      CT_Header : constant Header :=
        (Name  => To_Unbounded_String ("Content-Type"),
         Value => To_Unbounded_String ("application/json"));
      All_Headers       : Header_Array (1 .. Headers'Length + 1);
      Handle            : constant CURL_Handle := curl_easy_init;
      C_URL             : chars_ptr   := New_String (URL);
      C_Body            : chars_ptr   := New_String (Body_JSON);
      Slist             : CURL_Slist  := Null_Slist;
      Code              : CURL_Code;
      HTTP_Code         : aliased long := 0;
      Effective_Timeout : constant long :=
        (if Timeout_Ms = 0 then long (Default_Timeout_Ms)
         else long (Timeout_Ms));
      Result : Response;
      pragma Warnings (Off, Code);  --  curl_easy_setopt return values intentionally discarded
   begin
      All_Headers (1) := CT_Header;
      All_Headers (2 .. All_Headers'Last) := Headers;

      Streaming_Proc := On_Chunk;
      Set_Unbounded_String (Streaming_Buffer, "");

      --  SSRF guard.
      if not Is_Safe_URL (URL) then
         Set_Unbounded_String (Result.Error,
           "SSRF blocked: URL targets a private or reserved address");
         Free (C_Body);
         Free (C_URL);
         return Result;
      end if;

      if Handle = Null_CURL then
         Set_Unbounded_String (Result.Error, "curl_easy_init failed");
         Free (C_Body);
         Free (C_URL);
         return Result;
      end if;

      Code := curl_easy_setopt_cstr (Handle, CURLOPT_URL, C_URL);
      Code := curl_easy_setopt_long (Handle, CURLOPT_SSL_VERIFYPEER, 1);
      Code := curl_easy_setopt_long (Handle, CURLOPT_SSL_VERIFYHOST, 2);
      Code := curl_easy_setopt_long (Handle, CURLOPT_FOLLOWLOCATION, 1);
      Code := curl_easy_setopt_long (Handle, CURLOPT_MAXREDIRS, 5);
      Code := curl_easy_setopt_long
        (Handle, CURLOPT_TIMEOUT_MS, Effective_Timeout);
      Code := curl_easy_setopt_fn
        (Handle, CURLOPT_WRITEFUNCTION, Write_CB_Streaming'Access);

      for H of All_Headers loop
         declare
            Header_Str : constant String :=
              To_String (H.Name) & ": " & To_String (H.Value);
            C_H        : chars_ptr := New_String (Header_Str);
         begin
            Slist := curl_slist_append (Slist, C_H);
            Free (C_H);
         end;
      end loop;
      if Slist /= Null_Slist then
         Code := curl_easy_setopt_ptr
           (Handle, CURLOPT_HTTPHEADER, System.Address (Slist));
      end if;

      Code := curl_easy_setopt_long (Handle, CURLOPT_POST, 1);
      Code := curl_easy_setopt_cstr (Handle, CURLOPT_POSTFIELDS, C_Body);
      Code := curl_easy_perform (Handle);

      if Code = CURLE_OPERATION_TIMEDOUT then
         Set_Unbounded_String
           (Result.Error,
            "Request timed out after" & long'Image (Effective_Timeout) & "ms");
      elsif Code /= CURLE_OK then
         Set_Unbounded_String
           (Result.Error,
            "curl_easy_perform error code:" & CURL_Code'Image (Code));
      else
         Code := curl_easy_getinfo_long
           (Handle, CURLINFO_RESPONSE_CODE, HTTP_Code'Access);
         Result.Status_Code := Natural (HTTP_Code);
      end if;

      if Slist /= Null_Slist then
         curl_slist_free_all (Slist);
      end if;
      curl_easy_cleanup (Handle);
      Free (C_Body);
      Free (C_URL);

      --  Flush any partial line remaining in the buffer.
      if Streaming_Proc /= null and then Length (Streaming_Buffer) > 0 then
         Streaming_Proc (To_String (Streaming_Buffer));
         Set_Unbounded_String (Streaming_Buffer, "");
      end if;
      Streaming_Proc := null;
      return Result;
   end Post_JSON_Streaming;

end HTTP.Client;
