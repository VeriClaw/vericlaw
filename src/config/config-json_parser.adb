with Ada.Containers.Vectors;

package body Config.JSON_Parser
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Internal node types (Taft Amendment completion)
   ---------------------------------------------------------------------------

   type JSON_Kind is
     (JSON_Null, JSON_Boolean, JSON_Integer, JSON_String, JSON_Object,
      JSON_Array);

   type JSON_Pair is record
      Key   : Unbounded_String;
      Value : JSON_Node_Ptr;
   end record;

   package Pair_Vec is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => JSON_Pair);

   package Node_Vec is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => JSON_Node_Ptr);

   --  Full type completing the Taft Amendment declaration in the spec.
   type JSON_Node (Kind : JSON_Kind := JSON_Null) is record
      case Kind is
         when JSON_Null    => null;
         when JSON_Boolean => Bool  : Boolean      := False;
         when JSON_Integer => Int   : Long_Integer := 0;
         when JSON_String  => Str   : Unbounded_String;
         when JSON_Object  => Pairs : Pair_Vec.Vector;
         when JSON_Array   => Elems : Node_Vec.Vector;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Node allocation
   ---------------------------------------------------------------------------

   function New_Null return JSON_Node_Ptr is
   begin
      return new JSON_Node (Kind => JSON_Null);
   end New_Null;

   function New_Bool (V : Boolean) return JSON_Node_Ptr is
      N : constant JSON_Node_Ptr := new JSON_Node (Kind => JSON_Boolean);
   begin
      N.Bool := V;
      return N;
   end New_Bool;

   function New_Int (V : Long_Integer) return JSON_Node_Ptr is
      N : constant JSON_Node_Ptr := new JSON_Node (Kind => JSON_Integer);
   begin
      N.Int := V;
      return N;
   end New_Int;

   function New_Str (V : String) return JSON_Node_Ptr is
      N : constant JSON_Node_Ptr := new JSON_Node (Kind => JSON_String);
   begin
      Set_Unbounded_String (N.Str, V);
      return N;
   end New_Str;

   function New_Str_UB (V : Unbounded_String) return JSON_Node_Ptr is
      N : constant JSON_Node_Ptr := new JSON_Node (Kind => JSON_String);
   begin
      N.Str := V;
      return N;
   end New_Str_UB;

   function New_Object return JSON_Node_Ptr is
   begin
      return new JSON_Node (Kind => JSON_Object);
   end New_Object;

   function New_Array_Node return JSON_Node_Ptr is
   begin
      return new JSON_Node (Kind => JSON_Array);
   end New_Array_Node;

   ---------------------------------------------------------------------------
   --  Serialiser
   ---------------------------------------------------------------------------

   procedure Append_Escaped_Str
     (R : in out Unbounded_String; S : Unbounded_String)
   is
      C : Character;
   begin
      Append (R, '"');
      for I in 1 .. Length (S) loop
         C := Element (S, I);
         case C is
            when '"'      => Append (R, "\""");   --  \"
            when '\'      => Append (R, "\\");    --  \\
            when ASCII.LF => Append (R, "\n");
            when ASCII.HT => Append (R, "\t");
            when ASCII.CR => Append (R, "\r");
            when ASCII.BS => Append (R, "\b");
            when ASCII.FF => Append (R, "\f");
            when others   => Append (R, C);
         end case;
      end loop;
      Append (R, '"');
   end Append_Escaped_Str;

   procedure Serialize_Node (N : JSON_Node_Ptr; R : in out Unbounded_String) is
   begin
      if N = null then
         Append (R, "null");
         return;
      end if;
      case N.Kind is
         when JSON_Null    =>
            Append (R, "null");

         when JSON_Boolean =>
            if N.Bool then Append (R, "true"); else Append (R, "false"); end if;

         when JSON_Integer =>
            declare
               S : constant String := N.Int'Image;
            begin
               --  Long_Integer'Image prefixes a space for non-negative values
               if S'Length > 0 and then S (S'First) = ' ' then
                  Append (R, S (S'First + 1 .. S'Last));
               else
                  Append (R, S);
               end if;
            end;

         when JSON_String  =>
            Append_Escaped_Str (R, N.Str);

         when JSON_Object  =>
            Append (R, '{');
            for I in N.Pairs.First_Index .. N.Pairs.Last_Index loop
               if I > N.Pairs.First_Index then
                  Append (R, ',');
               end if;
               Append_Escaped_Str (R, N.Pairs.Element (I).Key);
               Append (R, ':');
               Serialize_Node (N.Pairs.Element (I).Value, R);
            end loop;
            Append (R, '}');

         when JSON_Array   =>
            Append (R, '[');
            for I in N.Elems.First_Index .. N.Elems.Last_Index loop
               if I > N.Elems.First_Index then
                  Append (R, ',');
               end if;
               Serialize_Node (N.Elems.Element (I), R);
            end loop;
            Append (R, ']');
      end case;
   end Serialize_Node;

   ---------------------------------------------------------------------------
   --  Recursive-descent parser (nested subprograms share Pos/Source state)
   ---------------------------------------------------------------------------

   function Parse (Source : String) return Parse_Result is
      Pos : Natural  := Source'First;
      Len : constant Natural := Source'Last;

      function Cur return Character is
      begin
         if Pos <= Len then return Source (Pos); else return ASCII.NUL; end if;
      end Cur;

      procedure Skip_WS is
      begin
         while Pos <= Len and then
               (Source (Pos) = ' '    or else
                Source (Pos) = ASCII.HT or else
                Source (Pos) = ASCII.LF or else
                Source (Pos) = ASCII.CR)
         loop
            Pos := Pos + 1;
         end loop;
      end Skip_WS;

      --  Forward declaration — needed so Object/Array parsers can call it.
      function Parse_Value return JSON_Node_Ptr;

      function Parse_String_Lit return JSON_Node_Ptr is
         Buf : Unbounded_String;
         C   : Character;
      begin
         if Pos > Len or else Source (Pos) /= '"' then return null; end if;
         Pos := Pos + 1;
         loop
            if Pos > Len then return null; end if;
            C   := Source (Pos);
            Pos := Pos + 1;
            if C = '"' then
               exit;
            elsif C = '\' then
               if Pos > Len then return null; end if;
               C   := Source (Pos);
               Pos := Pos + 1;
               case C is
                  when '"'  => Append (Buf, '"');
                  when '\'  => Append (Buf, '\');
                  when '/'  => Append (Buf, '/');
                  when 'n'  => Append (Buf, ASCII.LF);
                  when 't'  => Append (Buf, ASCII.HT);
                  when 'r'  => Append (Buf, ASCII.CR);
                  when 'b'  => Append (Buf, ASCII.BS);
                  when 'f'  => Append (Buf, ASCII.FF);
                  when 'u'  =>
                     --  \uXXXX: consume 4 hex digits, emit placeholder
                     for J in 1 .. 4 loop
                        if Pos <= Len then Pos := Pos + 1; end if;
                     end loop;
                     Append (Buf, '?');
                  when others => Append (Buf, C);
               end case;
            else
               Append (Buf, C);
            end if;
         end loop;
         return New_Str_UB (Buf);
      end Parse_String_Lit;

      function Parse_Number return JSON_Node_Ptr is
         Neg : Boolean      := False;
         Val : Long_Integer := 0;
      begin
         if Pos <= Len and then Source (Pos) = '-' then
            Neg := True;
            Pos := Pos + 1;
         end if;
         while Pos <= Len and then Source (Pos) in '0' .. '9' loop
            Val := Val * 10 +
                   Long_Integer (Character'Pos (Source (Pos)) -
                                 Character'Pos ('0'));
            Pos := Pos + 1;
         end loop;
         --  Skip fractional part (store as integer)
         if Pos <= Len and then Source (Pos) = '.' then
            Pos := Pos + 1;
            while Pos <= Len and then Source (Pos) in '0' .. '9' loop
               Pos := Pos + 1;
            end loop;
         end if;
         --  Skip exponent
         if Pos <= Len and then
            (Source (Pos) = 'e' or else Source (Pos) = 'E')
         then
            Pos := Pos + 1;
            if Pos <= Len and then
               (Source (Pos) = '+' or else Source (Pos) = '-')
            then
               Pos := Pos + 1;
            end if;
            while Pos <= Len and then Source (Pos) in '0' .. '9' loop
               Pos := Pos + 1;
            end loop;
         end if;
         if Neg then Val := -Val; end if;
         return New_Int (Val);
      end Parse_Number;

      function Parse_Object_Lit return JSON_Node_Ptr is
         N    : constant JSON_Node_Ptr := New_Object;
         K, V : JSON_Node_Ptr;
      begin
         Pos := Pos + 1;  --  skip '{'
         Skip_WS;
         if Cur = '}' then Pos := Pos + 1; return N; end if;
         loop
            Skip_WS;
            K := Parse_String_Lit;
            if K = null then return N; end if;
            Skip_WS;
            if Cur /= ':' then return N; end if;
            Pos := Pos + 1;
            Skip_WS;
            V := Parse_Value;
            if V = null then return N; end if;
            N.Pairs.Append ((Key => K.Str, Value => V));
            Skip_WS;
            if Cur = '}' then
               Pos := Pos + 1;
               exit;
            elsif Cur = ',' then
               Pos := Pos + 1;
            else
               exit;
            end if;
         end loop;
         return N;
      end Parse_Object_Lit;

      function Parse_Array_Lit return JSON_Node_Ptr is
         N : constant JSON_Node_Ptr := New_Array_Node;
         V : JSON_Node_Ptr;
      begin
         Pos := Pos + 1;  --  skip '['
         Skip_WS;
         if Cur = ']' then Pos := Pos + 1; return N; end if;
         loop
            Skip_WS;
            V := Parse_Value;
            if V = null then return N; end if;
            N.Elems.Append (V);
            Skip_WS;
            if Cur = ']' then
               Pos := Pos + 1;
               exit;
            elsif Cur = ',' then
               Pos := Pos + 1;
            else
               exit;
            end if;
         end loop;
         return N;
      end Parse_Array_Lit;

      function Parse_Literal (S : String) return Boolean is
      begin
         for I in S'Range loop
            if Pos > Len or else Source (Pos) /= S (I) then
               return False;
            end if;
            Pos := Pos + 1;
         end loop;
         return True;
      end Parse_Literal;

      function Parse_Value return JSON_Node_Ptr is
      begin
         case Cur is
            when '{'                =>  return Parse_Object_Lit;
            when '['                =>  return Parse_Array_Lit;
            when '"'                =>  return Parse_String_Lit;
            when 't'                =>
               if Parse_Literal ("true")  then return New_Bool (True);  end if;
               return null;
            when 'f'                =>
               if Parse_Literal ("false") then return New_Bool (False); end if;
               return null;
            when 'n'                =>
               if Parse_Literal ("null")  then return New_Null;         end if;
               return null;
            when '-' | '0' .. '9'  =>  return Parse_Number;
            when others             =>  return null;
         end case;
      end Parse_Value;

      Root   : JSON_Node_Ptr := null;
      Result : Parse_Result;
   begin
      Skip_WS;
      Root := Parse_Value;
      if Root = null then
         Set_Unbounded_String (Result.Error, "JSON parse error");
         Result.Valid := False;
      else
         Result.Root.Ptr := Root;
         Result.Valid    := True;
      end if;
      return Result;
   exception
      when others =>
         Set_Unbounded_String (Result.Error, "JSON parse exception");
         Result.Valid := False;
         return Result;
   end Parse;

   ---------------------------------------------------------------------------
   --  Internal helpers
   ---------------------------------------------------------------------------

   function Find_Field (N : JSON_Node_Ptr; Key : String) return JSON_Node_Ptr is
   begin
      if N = null or else N.Kind /= JSON_Object then return null; end if;
      for I in N.Pairs.First_Index .. N.Pairs.Last_Index loop
         if To_String (N.Pairs.Element (I).Key) = Key then
            return N.Pairs.Element (I).Value;
         end if;
      end loop;
      return null;
   end Find_Field;

   --  Update existing key or append new pair.
   procedure Set_Or_Append
     (N : JSON_Node_Ptr; Key : String; Value : JSON_Node_Ptr)
   is
   begin
      if N = null or else N.Kind /= JSON_Object then return; end if;
      for I in N.Pairs.First_Index .. N.Pairs.Last_Index loop
         if To_String (N.Pairs.Element (I).Key) = Key then
            N.Pairs.Replace_Element
              (I, (Key => N.Pairs.Element (I).Key, Value => Value));
            return;
         end if;
      end loop;
      N.Pairs.Append ((Key => To_Unbounded_String (Key), Value => Value));
   end Set_Or_Append;

   ---------------------------------------------------------------------------
   --  Public API
   ---------------------------------------------------------------------------

   function Get_String
     (V : JSON_Value_Type; Key : String; Default : String := "") return String
   is
      F : constant JSON_Node_Ptr := Find_Field (V.Ptr, Key);
   begin
      if F /= null and then F.Kind = JSON_String then
         return To_String (F.Str);
      end if;
      return Default;
   end Get_String;

   function Get_Integer
     (V : JSON_Value_Type; Key : String; Default : Integer := 0) return Integer
   is
      F : constant JSON_Node_Ptr := Find_Field (V.Ptr, Key);
   begin
      if F /= null and then F.Kind = JSON_Integer then
         return Integer (F.Int);
      end if;
      return Default;
   end Get_Integer;

   function Get_Boolean
     (V       : JSON_Value_Type;
      Key     : String;
      Default : Boolean := False) return Boolean
   is
      F : constant JSON_Node_Ptr := Find_Field (V.Ptr, Key);
   begin
      if F /= null and then F.Kind = JSON_Boolean then
         return F.Bool;
      end if;
      return Default;
   end Get_Boolean;

   function Get_Object
     (V : JSON_Value_Type; Key : String) return JSON_Value_Type
   is
      F : constant JSON_Node_Ptr := Find_Field (V.Ptr, Key);
   begin
      if F /= null then return (Ptr => F); end if;
      return (Ptr => New_Object);
   end Get_Object;

   function Has_Key (V : JSON_Value_Type; Key : String) return Boolean is
   begin
      return Find_Field (V.Ptr, Key) /= null;
   end Has_Key;

   function Value_To_Array (V : JSON_Value_Type) return JSON_Array_Type is
   begin
      return (Ptr => V.Ptr);
   end Value_To_Array;

   function Array_Length (A : JSON_Array_Type) return Natural is
   begin
      if A.Ptr = null or else A.Ptr.Kind /= JSON_Array then return 0; end if;
      return Natural (A.Ptr.Elems.Length);
   end Array_Length;

   function Array_Item
     (A : JSON_Array_Type; I : Positive) return JSON_Value_Type
   is
   begin
      if A.Ptr = null or else A.Ptr.Kind /= JSON_Array then
         return (Ptr => null);
      end if;
      if I in A.Ptr.Elems.First_Index .. A.Ptr.Elems.Last_Index then
         return (Ptr => A.Ptr.Elems.Element (I));
      end if;
      return (Ptr => null);
   end Array_Item;

   function To_JSON_String (V : JSON_Value_Type) return String is
      R : Unbounded_String;
   begin
      Serialize_Node (V.Ptr, R);
      return To_String (R);
   end To_JSON_String;

   function Escape_JSON_String (S : String) return String is
      R  : Unbounded_String;
      UB : Unbounded_String;
   begin
      Set_Unbounded_String (UB, S);
      Append_Escaped_Str (R, UB);
      return To_String (R);
   end Escape_JSON_String;

   function Build_Object return JSON_Value_Type is
   begin
      return (Ptr => New_Object);
   end Build_Object;

   function Build_Array return JSON_Value_Type is
   begin
      return (Ptr => New_Array_Node);
   end Build_Array;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : String)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Object; end if;
      Set_Or_Append (V.Ptr, Key, New_Str (Value));
   end Set_Field;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : Integer)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Object; end if;
      Set_Or_Append (V.Ptr, Key, New_Int (Long_Integer (Value)));
   end Set_Field;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : Boolean)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Object; end if;
      Set_Or_Append (V.Ptr, Key, New_Bool (Value));
   end Set_Field;

   procedure Set_Field
     (V     : in out JSON_Value_Type;
      Key   : String;
      Value : JSON_Value_Type)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Object; end if;
      Set_Or_Append (V.Ptr, Key, Value.Ptr);
   end Set_Field;

   procedure Append_Array
     (V : in out JSON_Value_Type; Item : JSON_Value_Type)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Array_Node; end if;
      V.Ptr.Elems.Append (Item.Ptr);
   end Append_Array;

   procedure Append_Array
     (V : in out JSON_Value_Type; Item : String)
   is
   begin
      if V.Ptr = null then V.Ptr := New_Array_Node; end if;
      V.Ptr.Elems.Append (New_Str (Item));
   end Append_Array;

end Config.JSON_Parser;
