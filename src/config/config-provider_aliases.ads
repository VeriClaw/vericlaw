--  Config.Provider_Aliases — OpenAI-compatible provider presets.
--  Each alias maps to a base URL + default model for the
--  OpenAI_Compatible provider kind.

package Config.Provider_Aliases
  with SPARK_Mode => Off
is

   type Alias_Info is record
      Name          : String (1 .. 20);
      Name_Length   : Natural;
      Base_URL      : String (1 .. 80);
      URL_Length    : Natural;
      Default_Model : String (1 .. 80);
      Model_Length  : Natural;
      Needs_Key     : Boolean;
   end record;

   Max_Aliases : constant := 12;
   type Alias_Index is range 1 .. Max_Aliases;
   type Alias_Array is array (Alias_Index) of Alias_Info;

   Alias_Count : constant Natural := 9;

   --  Get alias by index (1..Alias_Count).
   function Get_Alias (Idx : Alias_Index) return Alias_Info;

   --  Lookup by name (case-insensitive).
   --  Returns True and sets Info if found.
   procedure Lookup
     (Name  : String;
      Info  : out Alias_Info;
      Found : out Boolean);

end Config.Provider_Aliases;
