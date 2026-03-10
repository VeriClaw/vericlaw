with Ada.Characters.Handling;

package body Config.Provider_Aliases is

   function Pad_Name (S : String) return String is
      Result : String (1 .. 20) := (others => ' ');
   begin
      Result (1 .. S'Length) := S;
      return Result;
   end Pad_Name;

   function Pad_URL (S : String) return String is
      Result : String (1 .. 80) := (others => ' ');
   begin
      Result (1 .. S'Length) := S;
      return Result;
   end Pad_URL;

   function Pad_Model (S : String) return String is
      Result : String (1 .. 80) := (others => ' ');
   begin
      Result (1 .. S'Length) := S;
      return Result;
   end Pad_Model;

   Blank : constant Alias_Info :=
     (Name          => (others => ' '),
      Name_Length   => 0,
      Base_URL      => (others => ' '),
      URL_Length    => 0,
      Default_Model => (others => ' '),
      Model_Length  => 0,
      Needs_Key     => False);

   Aliases : constant Alias_Array :=
     (1  =>
        (Name        => Pad_Name ("groq"),
         Name_Length => 4,
         Base_URL    => Pad_URL ("https://api.groq.com/openai/v1"),
         URL_Length  => 30,
         Default_Model => Pad_Model ("llama-3.3-70b-versatile"),
         Model_Length  => 23,
         Needs_Key     => True),
      2  =>
        (Name        => Pad_Name ("mistral"),
         Name_Length => 7,
         Base_URL    => Pad_URL ("https://api.mistral.ai/v1"),
         URL_Length  => 25,
         Default_Model => Pad_Model ("mistral-large-latest"),
         Model_Length  => 20,
         Needs_Key     => True),
      3  =>
        (Name        => Pad_Name ("deepseek"),
         Name_Length => 8,
         Base_URL    => Pad_URL ("https://api.deepseek.com/v1"),
         URL_Length  => 27,
         Default_Model => Pad_Model ("deepseek-chat"),
         Model_Length  => 13,
         Needs_Key     => True),
      4  =>
        (Name        => Pad_Name ("xai"),
         Name_Length => 3,
         Base_URL    => Pad_URL ("https://api.x.ai/v1"),
         URL_Length  => 19,
         Default_Model => Pad_Model ("grok-2"),
         Model_Length  => 6,
         Needs_Key     => True),
      5  =>
        (Name        => Pad_Name ("openrouter"),
         Name_Length => 10,
         Base_URL    => Pad_URL ("https://openrouter.ai/api/v1"),
         URL_Length  => 28,
         Default_Model => Pad_Model ("auto"),
         Model_Length  => 4,
         Needs_Key     => True),
      6  =>
        (Name        => Pad_Name ("perplexity"),
         Name_Length => 10,
         Base_URL    => Pad_URL ("https://api.perplexity.ai"),
         URL_Length  => 24,
         Default_Model => Pad_Model ("sonar-pro"),
         Model_Length  => 9,
         Needs_Key     => True),
      7  =>
        (Name        => Pad_Name ("together"),
         Name_Length => 8,
         Base_URL    =>
           Pad_URL ("https://api.together.xyz/v1"),
         URL_Length  => 27,
         Default_Model =>
           Pad_Model
             ("meta-llama/Llama-3.3-70B-Instruct-Turbo"),
         Model_Length  => 40,
         Needs_Key     => True),
      8  =>
        (Name        => Pad_Name ("fireworks"),
         Name_Length => 9,
         Base_URL    =>
           Pad_URL
             ("https://api.fireworks.ai/inference/v1"),
         URL_Length  => 36,
         Default_Model =>
           Pad_Model
             ("accounts/fireworks/models/llama-v3p3-70b-instruct"),
         Model_Length  => 49,
         Needs_Key     => True),
      9  =>
        (Name        => Pad_Name ("cerebras"),
         Name_Length => 8,
         Base_URL    => Pad_URL ("https://api.cerebras.ai/v1"),
         URL_Length  => 25,
         Default_Model => Pad_Model ("llama-3.3-70b"),
         Model_Length  => 13,
         Needs_Key     => True),
      10 => Blank,
      11 => Blank,
      12 => Blank);

   function Get_Alias (Idx : Alias_Index) return Alias_Info is
   begin
      return Aliases (Idx);
   end Get_Alias;

   procedure Lookup
     (Name  : String;
      Info  : out Alias_Info;
      Found : out Boolean)
   is
      use Ada.Characters.Handling;

      Lower_Name : String := Name;
   begin
      for I in Lower_Name'Range loop
         Lower_Name (I) := To_Lower (Lower_Name (I));
      end loop;

      for I in 1 .. Alias_Count loop
         declare
            Idx : constant Alias_Index := Alias_Index (I);
            A   : Alias_Info renames Aliases (Idx);
            Stored : String renames
              A.Name (1 .. A.Name_Length);
            Lower_Stored : String := Stored;
         begin
            for J in Lower_Stored'Range loop
               Lower_Stored (J) := To_Lower (Lower_Stored (J));
            end loop;

            if Lower_Name = Lower_Stored then
               Info  := A;
               Found := True;
               return;
            end if;
         end;
      end loop;

      Info  := Blank;
      Found := False;
   end Lookup;

end Config.Provider_Aliases;
