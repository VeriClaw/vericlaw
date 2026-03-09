with Build_Info;

package body Terminal.Style is

   Color_Enabled : Boolean := True;

   procedure Set_Enabled (On : Boolean) is
   begin
      Color_Enabled := On;
   end Set_Enabled;

   function Is_Enabled return Boolean is (Color_Enabled);

   ---------------------------------------------------------------------------
   function C (Code : String; Text : String) return String is
   begin
      if not Color_Enabled then
         return Text;
      end if;
      return Code & Text & Reset_Code;
   end C;

   ---------------------------------------------------------------------------
   --  Theme helpers
   ---------------------------------------------------------------------------

   function Brand   (Text : String) return String is
   begin return C (Bold_Cyan_Code, Text); end Brand;

   function Success (Text : String) return String is
   begin return C (Green_Code, Text); end Success;

   function Error (Text : String) return String is
   begin return C (Red_Code, Text); end Error;

   function Warn (Text : String) return String is
   begin return C (Yellow_Code, Text); end Warn;

   function Heading (Text : String) return String is
   begin return C (Bold_Code & White_Code, Text); end Heading;

   function Muted (Text : String) return String is
   begin return C (Dim_Code, Text); end Muted;

   function Cmd (Text : String) return String is
   begin return C (Bold_Cyan_Code, Text); end Cmd;

   ---------------------------------------------------------------------------
   --  Status symbols
   ---------------------------------------------------------------------------

   function Check return String is
   begin
      if Color_Enabled then
         return Green_Code & "✓" & Reset_Code;
      else
         return "OK";
      end if;
   end Check;

   function Cross return String is
   begin
      if Color_Enabled then
         return Red_Code & "✗" & Reset_Code;
      else
         return "FAIL";
      end if;
   end Cross;

   function Bullet return String is
   begin
      if Color_Enabled then
         return Cyan_Code & "›" & Reset_Code;
      else
         return "-";
      end if;
   end Bullet;

   ---------------------------------------------------------------------------
   --  ASCII-art banner.  Compact 5-line block art for "VeriClaw".
   ---------------------------------------------------------------------------
   NL : constant Character := ASCII.LF;

   Art : constant String :=
     " __     __        _  ____ _                " & NL &
     " \ \   / /__ _ __(_)/ ___| | __ ___      __" & NL &
     "  \ \ / / _ \ '__| | |   | |/ _` \ \ /\ / /" & NL &
     "   \ V /  __/ |  | | |___| | (_| |\ V  V / " & NL &
     "    \_/ \___|_|  |_|\____|_|\__,_| \_/\_/  ";

   function Banner return String is
      Ver_Line : constant String :=
        "  v" & Build_Info.Version &
        "  —  formally verified AI runtime";
   begin
      if Color_Enabled then
         return Bold_Cyan_Code & Art & Reset_Code & NL &
                Dim_Code & Ver_Line & Reset_Code;
      else
         return Art & NL & Ver_Line;
      end if;
   end Banner;

end Terminal.Style;
