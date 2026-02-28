with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;

package body Tools.Browser
  with SPARK_Mode => Off
is

   function Browse (URL : String; Timeout_Ms : Positive := 15_000)
     return Browse_Result
   is
      Bridge : constant String := To_String (Bridge_URL);
      Body_JSON : constant String :=
        "{""url"":""" & URL & """,""timeout_ms"":" & Positive'Image (Timeout_Ms) & "}";

      JSON_Hdrs : constant HTTP.Client.Header_Array :=
        [1 => (Name  => To_Unbounded_String ("Content-Type"),
               Value => To_Unbounded_String ("application/json")),
         2 => (Name  => To_Unbounded_String ("Accept"),
               Value => To_Unbounded_String ("application/json"))];

      Http_Resp : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON
          (URL        => Bridge & "/browse",
           Headers    => JSON_Hdrs,
           Body_JSON  => Body_JSON,
           Timeout_Ms => Timeout_Ms + 5_000);

      Result : Browse_Result;
   begin
      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error,
            "browser-bridge HTTP error " & Http_Resp.Status_Code'Image);
         return Result;
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Http_Resp.Body_Text));
      begin
         if not PR.Valid then
            Set_Unbounded_String (Result.Error, "Invalid JSON from browser-bridge");
            return Result;
         end if;

         if not Get_Boolean (PR.Root, "ok", False) then
            Set_Unbounded_String
              (Result.Error, Get_String (PR.Root, "error", "browser-bridge error"));
            return Result;
         end if;

         Set_Unbounded_String (Result.Text,  Get_String (PR.Root, "text"));
         Set_Unbounded_String (Result.Title, Get_String (PR.Root, "title"));
         Result.Success := True;
      end;
      return Result;
   end Browse;

   function Screenshot (URL : String; Timeout_Ms : Positive := 15_000)
     return Screenshot_Result
   is
      Bridge : constant String := To_String (Bridge_URL);
      Body_JSON : constant String :=
        "{""url"":""" & URL & """,""timeout_ms"":" & Positive'Image (Timeout_Ms) & "}";

      JSON_Hdrs : constant HTTP.Client.Header_Array :=
        [1 => (Name  => To_Unbounded_String ("Content-Type"),
               Value => To_Unbounded_String ("application/json")),
         2 => (Name  => To_Unbounded_String ("Accept"),
               Value => To_Unbounded_String ("application/json"))];

      Http_Resp : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON
          (URL        => Bridge & "/screenshot",
           Headers    => JSON_Hdrs,
           Body_JSON  => Body_JSON,
           Timeout_Ms => Timeout_Ms + 5_000);

      Result : Screenshot_Result;
   begin
      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error,
            "browser-bridge HTTP error " & Http_Resp.Status_Code'Image);
         return Result;
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Http_Resp.Body_Text));
      begin
         if not PR.Valid then
            Set_Unbounded_String (Result.Error, "Invalid JSON from browser-bridge");
            return Result;
         end if;

         if not Get_Boolean (PR.Root, "ok", False) then
            Set_Unbounded_String
              (Result.Error, Get_String (PR.Root, "error", "browser-bridge error"));
            return Result;
         end if;

         Set_Unbounded_String (Result.PNG_Base64, Get_String (PR.Root, "png_base64"));
         Set_Unbounded_String (Result.Title,      Get_String (PR.Root, "title"));
         Result.Success := True;
      end;
      return Result;
   end Screenshot;

end Tools.Browser;
