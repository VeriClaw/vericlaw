pragma SPARK_Mode (Off);
--  Terminal styling: ANSI escape codes, themed output functions, and
--  the VeriClaw ASCII-art banner.  All functions respect an Enabled
--  flag so that --no-color, NO_COLOR, and piped output produce plain text.
package Terminal.Style is

   --  Call once at startup after flag parsing.
   procedure Set_Enabled (On : Boolean);
   function  Is_Enabled return Boolean;

   ---------------------------------------------------------------------------
   --  Low-level: wrap text with an ANSI code.  Returns plain text when
   --  styling is disabled.
   ---------------------------------------------------------------------------
   function C (Code : String; Text : String) return String;

   ---------------------------------------------------------------------------
   --  ANSI escape constants (safe to embed directly when Enabled = True).
   ---------------------------------------------------------------------------
   Reset_Code : constant String := ASCII.ESC & "[0m";
   Bold_Code  : constant String := ASCII.ESC & "[1m";
   Dim_Code   : constant String := ASCII.ESC & "[2m";

   Red_Code    : constant String := ASCII.ESC & "[31m";
   Green_Code  : constant String := ASCII.ESC & "[32m";
   Yellow_Code : constant String := ASCII.ESC & "[33m";
   Blue_Code   : constant String := ASCII.ESC & "[34m";
   Cyan_Code   : constant String := ASCII.ESC & "[36m";
   White_Code  : constant String := ASCII.ESC & "[37m";

   Bold_Cyan_Code  : constant String := ASCII.ESC & "[1;36m";
   Bold_Green_Code : constant String := ASCII.ESC & "[1;32m";
   Bold_Red_Code   : constant String := ASCII.ESC & "[1;31m";

   ---------------------------------------------------------------------------
   --  Theme helpers — semantic wrappers around C().
   ---------------------------------------------------------------------------
   function Brand   (Text : String) return String;  --  bold cyan
   function Success (Text : String) return String;  --  green
   function Error   (Text : String) return String;  --  red
   function Warn    (Text : String) return String;  --  yellow
   function Heading (Text : String) return String;  --  bold white
   function Muted   (Text : String) return String;  --  dim
   function Cmd     (Text : String) return String;  --  bold cyan (same as Brand)

   ---------------------------------------------------------------------------
   --  Status symbols.
   ---------------------------------------------------------------------------
   function Check return String;   --  green "✓"
   function Cross return String;   --  red "✗"
   function Bullet return String;  --  cyan "›"

   ---------------------------------------------------------------------------
   --  VeriClaw ASCII-art banner (5 lines).
   ---------------------------------------------------------------------------
   function Banner return String;

end Terminal.Style;
