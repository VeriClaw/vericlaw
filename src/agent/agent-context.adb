with Ada.Numerics.Discrete_Random;
with Ada.Strings.Fixed;
with Ada.Directories;
with Ada.Streams.Stream_IO;
with Config.Schema;

package body Agent.Context
  with SPARK_Mode => Off
is

   package Rand_Char is new Ada.Numerics.Discrete_Random (Character);
   Rng : Rand_Char.Generator;

   Hex_Chars : constant String := "0123456789abcdef";

   function Make_Session_ID return String is
      Result : String (1 .. 16);
   begin
      Rand_Char.Reset (Rng);
      for I in Result'Range loop
         Result (I) :=
           Hex_Chars (1 + Character'Pos (Rand_Char.Random (Rng)) mod 16);
      end loop;
      return Result;
   end Make_Session_ID;

   procedure Append_Message
     (Conv    : in out Conversation;
      Role    : Agent.Context.Role;
      Content : String;
      Name    : String := "";
      Limit   : Config.Schema.History_Limit := Max_Stored_Messages)
   is
      History_Cap : constant Positive := Positive (Limit);
      New_Msg : constant Message :=
        (Role       => Role,
         Content    => To_Unbounded_String (Content),
         Name       => To_Unbounded_String (Name),
         Images     => [others => (others => Null_Unbounded_String)],
         Num_Images => 0);
   begin
      if Conv.Msg_Count > Natural (History_Cap) then
          if Conv.Messages (1).Role = System_Role and then History_Cap > 1 then
             declare
                Keep_Count : constant Natural := Natural (History_Cap) - 1;
                Source_First : constant Positive :=
                  Positive (Conv.Msg_Count - Keep_Count + 1);
             begin
                pragma Assert (Source_First <= Conv.Msg_Count);
                Conv.Messages (2 .. History_Cap) :=
                  Conv.Messages (Source_First .. Conv.Msg_Count);
             end;
          else
             declare
                Keep_Count : constant Natural := Natural (History_Cap);
                Source_First : constant Positive :=
                  Positive (Conv.Msg_Count - Keep_Count + 1);
             begin
                pragma Assert (Source_First <= Conv.Msg_Count);
                Conv.Messages (1 .. History_Cap) :=
                  Conv.Messages (Source_First .. Conv.Msg_Count);
             end;
          end if;
         Conv.Msg_Count := Natural (History_Cap);
      end if;

      if Conv.Msg_Count < Natural (History_Cap) then
         Conv.Msg_Count := Conv.Msg_Count + 1;
         Conv.Messages (Conv.Msg_Count) := New_Msg;
       else
          --  Evict oldest non-system message (shift left from index 2).
          --  Index 1 is always the system prompt if present; preserve it.
         declare
            Start : constant Positive :=
               (if Conv.Messages (1).Role = System_Role then 2 else 1);
         begin
            if Start < History_Cap then
               Conv.Messages (Start .. History_Cap - 1) :=
                 Conv.Messages (Start + 1 .. History_Cap);
            end if;
            Conv.Messages (History_Cap) := New_Msg;
            Conv.Msg_Count := Natural (History_Cap);
         end;
      end if;
   end Append_Message;

   function Last_User_Message (Conv : Conversation) return String is
   begin
      for I in reverse 1 .. Conv.Msg_Count loop
         if Conv.Messages (I).Role = User then
            return To_String (Conv.Messages (I).Content);
         end if;
      end loop;
      return "";
   end Last_User_Message;

   function Format_For_Provider
     (Conv : Conversation) return Message_Array
   is
   begin
      return Conv.Messages (1 .. Conv.Msg_Count);
   end Format_For_Provider;

   function Token_Estimate (Conv : Conversation) return Natural is
      Total : Natural := 0;
   begin
      for I in 1 .. Conv.Msg_Count loop
         Total := Total + Length (Conv.Messages (I).Content) / 4 + 4;
      end loop;
      return Total;
   end Token_Estimate;

   --  Internal helper: return at most Max characters from S.
   function Head (S : String; Max : Natural) return String is
   begin
      if S'Length <= Max then
         return S;
      end if;
      --  Reserve 3 chars for the ellipsis; guard against tiny Max values.
      if Max <= 3 then
         return "...";
      end if;
      return S (S'First .. S'First + Max - 4) & "...";
   end Head;

   procedure Compact_Oldest_Turn (Conv : in out Conversation) is
      Start : Positive;
   begin
      if Conv.Msg_Count < 2 then
         return;
      end if;

      Start :=
        (if Conv.Messages (1).Role = System_Role then 2 else 1);

      if Start > Conv.Msg_Count then
         return;
      end if;

      if Start + 1 <= Conv.Msg_Count
        and then Conv.Messages (Start).Role = User
        and then Conv.Messages (Start + 1).Role = Assistant
      then
         --  Pair found: replace with a single summary message, then left-shift.
         declare
            U_Head : constant String :=
              Head (To_String (Conv.Messages (Start).Content),
                    Compact_Summary_Len);
            A_Head : constant String :=
              Head (To_String (Conv.Messages (Start + 1).Content),
                    Compact_Summary_Len);
            Summary : constant String :=
              "[Earlier: " & U_Head & " → " & A_Head & "]";
         begin
            Conv.Messages (Start) :=
              (Role       => User,
               Content    => To_Unbounded_String (Summary),
               Name       => Null_Unbounded_String,
               Images     => [others => (others => Null_Unbounded_String)],
               Num_Images => 0);
            --  Remove the assistant message at Start+1 by left-shifting.
            for I in Start + 1 .. Conv.Msg_Count - 1 loop
               Conv.Messages (I) := Conv.Messages (I + 1);
            end loop;
            Conv.Msg_Count := Conv.Msg_Count - 1;
         end;
      else
         --  No pair: just drop the oldest non-system message.
         for I in Start .. Conv.Msg_Count - 1 loop
            Conv.Messages (I) := Conv.Messages (I + 1);
         end loop;
         Conv.Msg_Count := Conv.Msg_Count - 1;
      end if;
   end Compact_Oldest_Turn;

   function Compaction_Needed
     (Conv          : Conversation;
      Threshold_Pct : Config.Schema.Compact_Pct;
      Limit         : Config.Schema.History_Limit) return Boolean
   is
   begin
      if Threshold_Pct = 0 then
         return False;
      end if;
      return Conv.Msg_Count * 100 / Natural (Limit) >= Natural (Threshold_Pct);
   end Compaction_Needed;

   --  Base64 encoding table
   B64 : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   function Encode_Base64 (Data : Ada.Streams.Stream_Element_Array)
     return String
   is
      use Ada.Streams;
      Result : String (1 .. ((Data'Length + 2) / 3) * 4);
      Idx    : Positive := 1;
      I      : Stream_Element_Offset := Data'First;
      A, B, C : Stream_Element;
   begin
      while I <= Data'Last loop
         A := Data (I);
         B := (if I + 1 <= Data'Last then Data (I + 1) else 0);
         C := (if I + 2 <= Data'Last then Data (I + 2) else 0);
         Result (Idx)     := B64 (Integer (A / 4) + 1);
         Result (Idx + 1) := B64 (Integer ((A mod 4) * 16 + B / 16) + 1);
         if I + 1 <= Data'Last then
            Result (Idx + 2) := B64 (Integer ((B mod 16) * 4 + C / 64) + 1);
         else
            Result (Idx + 2) := '=';
         end if;
         if I + 2 <= Data'Last then
            Result (Idx + 3) := B64 (Integer (C mod 64) + 1);
         else
            Result (Idx + 3) := '=';
         end if;
         Idx := Idx + 4;
         I   := I + 3;
      end loop;
      return Result (1 .. Idx - 1);
   end Encode_Base64;

   function Detect_Media_Type (Path : String) return String is
      Len : constant Natural := Path'Length;
   begin
      if Len >= 4 then
         declare
            Ext : constant String := Path (Path'Last - 3 .. Path'Last);
         begin
            if Ext = ".jpg" or else Ext = ".JPG" then return "image/jpeg"; end if;
            if Ext = ".png" or else Ext = ".PNG" then return "image/png"; end if;
            if Ext = ".gif" or else Ext = ".GIF" then return "image/gif"; end if;
         end;
      end if;
      if Len >= 5 then
         declare
            Ext5 : constant String := Path (Path'Last - 4 .. Path'Last);
         begin
            if Ext5 = ".jpeg" or else Ext5 = ".JPEG" then return "image/jpeg"; end if;
            if Ext5 = ".webp" or else Ext5 = ".WEBP" then return "image/webp"; end if;
         end;
      end if;
      return "image/png";  -- default
   end Detect_Media_Type;

   procedure Parse_Image_Markers
     (Input    : String;
      Text_Out : out Unbounded_String;
      Images   : out Image_Array;
      Num_Imgs : out Natural)
   is
      use Ada.Strings.Fixed;
      Marker : constant String := "[IMAGE:";
      Pos    : Natural;
      Start  : Positive := Input'First;
   begin
      Text_Out := Null_Unbounded_String;
      Images   := [others => (others => Null_Unbounded_String)];
      Num_Imgs := 0;

      loop
         Pos := Index (Input (Start .. Input'Last), Marker);
         exit when Pos = 0 or else Num_Imgs >= Max_Images;

         --  Append text before the marker.
         if Pos > Start then
            Append (Text_Out, Input (Start .. Pos - 1));
         end if;

         --  Find closing bracket.
         declare
            Path_Start : constant Positive := Pos + Marker'Length;
            Close_Pos  : constant Natural :=
              Index (Input (Path_Start .. Input'Last), "]");
         begin
            if Close_Pos = 0 then
               --  No closing bracket; treat as literal text.
               Append (Text_Out, Input (Pos .. Input'Last));
               Start := Input'Last + 1;
               exit;
            end if;

            declare
               Ref : constant String := Input (Path_Start .. Close_Pos - 1);
               Max_Image_Size : constant := 10_000_000;  -- 10 MB

               function Is_Safe_Image_Path (P : String) return Boolean is
               begin
                  if Index (P, "..") > 0 then return False; end if;
                  if P'Length > 0 and then P (P'First) = '/' then
                     return False;
                  end if;
                  if P'Length > 0 and then P (P'First) = '~' then
                     return False;
                  end if;
                  return True;
               end Is_Safe_Image_Path;
            begin
               Num_Imgs := Num_Imgs + 1;
               Set_Unbounded_String (Images (Num_Imgs).Source_URL, Ref);
               Set_Unbounded_String
                 (Images (Num_Imgs).Media_Type, Detect_Media_Type (Ref));

               --  Check if it's a URL or file path.
               if (Ref'Length >= 7
                     and then Ref (Ref'First .. Ref'First + 6) = "http://")
                 or else (Ref'Length >= 8
                     and then Ref (Ref'First .. Ref'First + 7) = "https://")
               then
                  --  URL: pass through; provider will handle it.
                  Set_Unbounded_String (Images (Num_Imgs).Data, "");
               elsif Is_Safe_Image_Path (Ref)
                 and then Ada.Directories.Exists (Ref)
               then
                  --  Local file: read and base64-encode with size guard.
                  declare
                     use Ada.Streams.Stream_IO;
                     use Ada.Streams;
                     use type Ada.Directories.File_Size;
                     File_Size_Val : constant Ada.Directories.File_Size :=
                       Ada.Directories.Size (Ref);
                  begin
                     if File_Size_Val > Max_Image_Size then
                        Num_Imgs := Num_Imgs - 1;  -- too large
                     else
                        declare
                           Size   : constant Natural :=
                             Natural (File_Size_Val);
                           File   : File_Type;
                           Buffer : Stream_Element_Array
                             (1 .. Stream_Element_Offset (Size));
                           Last   : Stream_Element_Offset;
                        begin
                           Open (File, In_File, Ref);
                           begin
                              Read (File, Buffer, Last);
                              Close (File);
                           exception
                              when others =>
                                 Close (File);
                                 Num_Imgs := Num_Imgs - 1;
                                 goto Continue_Image;
                           end;
                           Set_Unbounded_String
                             (Images (Num_Imgs).Data,
                              Encode_Base64 (Buffer (1 .. Last)));
                        end;
                     end if;
                  exception
                     when others =>
                        Num_Imgs := Num_Imgs - 1;
                  end;
               else
                  --  Unsafe path or not a file — drop.
                  Num_Imgs := Num_Imgs - 1;
               end if;
            end;

            <<Continue_Image>>
            Start := Close_Pos + 1;
         end;
      end loop;

      --  Append remaining text.
      if Start <= Input'Last then
         Append (Text_Out, Input (Start .. Input'Last));
      end if;
   end Parse_Image_Markers;

end Agent.Context;
