with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Ada.Strings.Fixed;

pragma SPARK_Mode (Off);
package body Tools.Brave_Search is

   Brave_Search_URL : constant String :=
     "https://api.search.brave.com/res/v1/web/search";

   function Search
     (Query        : String;
      API_Key      : String;
      Num_Results  : Positive := 5) return Brave_Result
   is
      --  URL-encode only the most common characters.
      function Simple_URL_Encode (S : String) return String is
         Result : Unbounded_String;
      begin
         for C of S loop
            case C is
               when ' '  => Append (Result, "+");
               when '&'  => Append (Result, "%26");
               when '='  => Append (Result, "%3D");
               when '#'  => Append (Result, "%23");
               when '%'  => Append (Result, "%25");
               when others => Append (Result, C);
            end case;
         end loop;
         return To_String (Result);
      end Simple_URL_Encode;

      URL      : constant String :=
        Brave_Search_URL
        & "?q=" & Simple_URL_Encode (Query)
        & "&count=" & Positive'Image (Num_Results)
        & "&safesearch=moderate&text_decorations=0";

      Hdrs     : constant HTTP.Client.Header_Array :=
        (1 => (Name  => To_Unbounded_String ("Accept"),
               Value => To_Unbounded_String ("application/json")),
         2 => (Name  => To_Unbounded_String ("Accept-Encoding"),
               Value => To_Unbounded_String ("gzip")),
         3 => (Name  => To_Unbounded_String ("X-Subscription-Token"),
               Value => To_Unbounded_String (API_Key)));

      Http_Resp : constant HTTP.Client.Response :=
        HTTP.Client.Get (URL => URL, Headers => Hdrs, Timeout_Ms => 15_000);

      Result : Brave_Result;
   begin
      if not HTTP.Client.Is_Success (Http_Resp) then
         Set_Unbounded_String
           (Result.Error,
            "Brave Search HTTP error " & Http_Resp.Status_Code'Image);
         return Result;
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Http_Resp.Body_Text));
      begin
         if not PR.Valid then
            Set_Unbounded_String (Result.Error, "Invalid JSON from Brave API");
            return Result;
         end if;

         if Has_Key (PR.Root, "web") then
            declare
               Web   : constant JSON_Value_Type :=
                 Get_Object (PR.Root, "web");
               Items : constant JSON_Value_Type :=
                 Get_Object (Web, "results");
            begin
               declare
                  Items_Arr : constant JSON_Array_Type :=
                    Value_To_Array (Items);
               begin
                  for I in 1 .. Array_Length (Items_Arr) loop
                  exit when Result.Count >= Max_Results;
                  declare
                     Item : constant JSON_Value_Type := Array_Item (Items_Arr, I);
                  begin
                     Result.Count := Result.Count + 1;
                     Set_Unbounded_String
                       (Result.Results (Result.Count).Title,
                        Get_String (Item, "title"));
                     Set_Unbounded_String
                       (Result.Results (Result.Count).URL,
                        Get_String (Item, "url"));
                     Set_Unbounded_String
                       (Result.Results (Result.Count).Snippet,
                        Get_String (Item, "description"));
                  end;
               end loop;
            end;
         end;
         end if;

         Result.Success := True;
      end;
      return Result;
   end Search;

   function To_Agent_Text (R : Brave_Result) return String is
      Buf : Unbounded_String;
   begin
      if not R.Success then
         return "Search failed: " & To_String (R.Error);
      end if;
      if R.Count = 0 then
         return "No results found.";
      end if;
      for I in 1 .. R.Count loop
         Append (Buf, Natural'Image (I) & ". ");
         Append (Buf, To_String (R.Results (I).Title) & ASCII.LF);
         Append (Buf, "   " & To_String (R.Results (I).URL) & ASCII.LF);
         Append (Buf, "   " & To_String (R.Results (I).Snippet) & ASCII.LF);
         Append (Buf, ASCII.LF);
      end loop;
      return To_String (Buf);
   end To_Agent_Text;

end Tools.Brave_Search;
