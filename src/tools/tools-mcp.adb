with HTTP.Client;
with Config.JSON_Parser; use Config.JSON_Parser;
with Ada.Strings.Fixed;

package body Tools.MCP is

   --  Build the POST body for a tool call.
   function Build_Call_Body (Args_JSON : String) return String is
   begin
      if Args_JSON'Length = 0 or else Args_JSON = "{}" then
         return "{""arguments"":{}}";
      end if;
      return "{""arguments"":" & Args_JSON & "}";
   end Build_Call_Body;

   --  Return True when Str starts with Prefix.
   function Starts_With (Str, Prefix : String) return Boolean is
   begin
      return Str'Length >= Prefix'Length
        and then Str (Str'First .. Str'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   procedure Fetch_Tools
     (Bridge_URL : String;
      Tools      : out MCP_Tool_Array;
      Count      : out Natural)
   is
      URL       : constant String := Bridge_URL & "/tools";
      JSON_Hdrs : constant HTTP.Client.Header_Array :=
        (1 => (Name  => To_Unbounded_String ("Accept"),
               Value => To_Unbounded_String ("application/json")));
      Resp      : constant HTTP.Client.Response :=
        HTTP.Client.Get (URL, JSON_Hdrs, Timeout_Ms => 10_000);
   begin
      Count := 0;
      --  Zero-initialise every slot so callers see clean data.
      for I in Tools'Range loop
         Tools (I) := (others => <>);
      end loop;

      if not HTTP.Client.Is_Success (Resp) then
         return;
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Resp.Body_Text));
      begin
         if not PR.Valid then
            return;
         end if;

         declare
            Arr : constant JSON_Array_Type := Value_To_Array (PR.Root);
         begin
            for I in 1 .. Array_Length (Arr) loop
               exit when Count >= Max_MCP_Tools;
               declare
                  Item  : constant JSON_Value_Type := Array_Item (Arr, I);
                  TName : constant String := Get_String (Item, "name");
                  TDesc : constant String := Get_String (Item, "description");
                  TSchema : Unbounded_String;
               begin
                  if Has_Key (Item, "inputSchema") then
                     Set_Unbounded_String
                       (TSchema,
                        To_JSON_String (Get_Object (Item, "inputSchema")));
                  else
                     Set_Unbounded_String (TSchema, "{""type"":""object""}");
                  end if;

                  if TName'Length > 0 then
                     Count := Count + 1;
                     Set_Unbounded_String (Tools (Count).Name, TName);
                     Set_Unbounded_String (Tools (Count).Description, TDesc);
                     Tools (Count).Input_Schema := TSchema;
                  end if;
               end;
            end loop;
         end;
      end;
   end Fetch_Tools;

   function Execute
     (Bridge_URL : String;
      Name       : String;
      Args_JSON  : String) return String
   is
      URL       : constant String :=
        Bridge_URL & "/tools/" & Name & "/call";
      JSON_Hdrs : constant HTTP.Client.Header_Array :=
        (1 => (Name  => To_Unbounded_String ("Content-Type"),
               Value => To_Unbounded_String ("application/json")),
         2 => (Name  => To_Unbounded_String ("Accept"),
               Value => To_Unbounded_String ("application/json")));
      Body_Str  : constant String := Build_Call_Body (Args_JSON);
      Resp      : constant HTTP.Client.Response :=
        HTTP.Client.Post_JSON (URL, JSON_Hdrs, Body_Str, Timeout_Ms => 30_000);
   begin
      if not HTTP.Client.Is_Success (Resp) then
         return "";
      end if;

      declare
         PR : constant Parse_Result :=
           Parse (To_String (Resp.Body_Text));
      begin
         if not PR.Valid then
            return "";
         end if;
         return Get_String (PR.Root, "result");
      end;
   end Execute;

   procedure Append_Schemas
     (MCP_Tools  : MCP_Tool_Array;
      Count      : Natural;
      Schemas    : in out Tool_Schema_Array;
      Num        : in out Natural)
   is
   begin
      for I in 1 .. Count loop
         exit when Num >= Schemas'Last;
         Num := Num + 1;
         Schemas (Num) :=
           (Name        => MCP_Tools (I).Name,
            Description => MCP_Tools (I).Description,
            Parameters  => MCP_Tools (I).Input_Schema);
      end loop;
   end Append_Schemas;

end Tools.MCP;
