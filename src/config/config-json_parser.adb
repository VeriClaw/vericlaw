with GNATCOLL.JSON; use GNATCOLL.JSON;

pragma SPARK_Mode (Off);
package body Config.JSON_Parser is

   function Parse (Source : String) return Parse_Result is
      Result : Parse_Result;
   begin
      Result.Root  := Read (Source);
      Result.Valid := True;
      return Result;
   exception
      when E : others =>
         Result.Valid := False;
         Set_Unbounded_String
           (Result.Error, "JSON parse error: " & Source'Length'Image & " bytes");
         return Result;
   end Parse;

   function Get_String
     (V       : JSON_Value_Type;
      Key     : String;
      Default : String := "") return String
   is
   begin
      if V.Has_Field (Key) then
         declare
            Field : constant JSON_Value_Type := V.Get (Key);
         begin
            if Field.Kind = JSON_String_Type then
               return Field.Get;
            end if;
         end;
      end if;
      return Default;
   end Get_String;

   function Get_Integer
     (V       : JSON_Value_Type;
      Key     : String;
      Default : Integer := 0) return Integer
   is
   begin
      if V.Has_Field (Key) then
         declare
            Field : constant JSON_Value_Type := V.Get (Key);
         begin
            if Field.Kind = JSON_Int_Type then
               return Field.Get;
            end if;
         end;
      end if;
      return Default;
   end Get_Integer;

   function Get_Boolean
     (V       : JSON_Value_Type;
      Key     : String;
      Default : Boolean := False) return Boolean
   is
   begin
      if V.Has_Field (Key) then
         declare
            Field : constant JSON_Value_Type := V.Get (Key);
         begin
            if Field.Kind = JSON_Boolean_Type then
               return Field.Get;
            end if;
         end;
      end if;
      return Default;
   end Get_Boolean;

   function Get_Object
     (V   : JSON_Value_Type;
      Key : String) return JSON_Value_Type
   is
   begin
      if V.Has_Field (Key) then
         return V.Get (Key);
      end if;
      return Create_Object;
   end Get_Object;

   function Has_Key
     (V   : JSON_Value_Type;
      Key : String) return Boolean is
   begin
      return V.Has_Field (Key);
   end Has_Key;

   function To_JSON_String (V : JSON_Value_Type) return String is
   begin
      return V.Write;
   end To_JSON_String;

   function Escape_JSON_String (S : String) return String is
      --  Use GNATCOLL.JSON to properly escape the string.
      V : constant JSON_Value_Type := Create (S);
   begin
      return V.Write;
   end Escape_JSON_String;

   function Build_Object return JSON_Value_Type is
   begin
      return Create_Object;
   end Build_Object;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : String) is
   begin
      V.Set_Field (Key, Value);
   end Set_Field;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : Integer) is
   begin
      V.Set_Field (Key, Value);
   end Set_Field;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : Boolean) is
   begin
      V.Set_Field (Key, Value);
   end Set_Field;

   procedure Set_Field
     (V : in out JSON_Value_Type; Key : String; Value : JSON_Value_Type) is
   begin
      V.Set_Field (Key, Value);
   end Set_Field;

   function Build_Array return JSON_Value_Type is
      A : JSON_Array;
   begin
      return Create (A);
   end Build_Array;

   procedure Append_Array
     (V : in out JSON_Value_Type; Item : JSON_Value_Type)
   is
      A : JSON_Array := V.Get;
   begin
      Append (A, Item);
      V := Create (A);
   end Append_Array;

   procedure Append_Array
     (V : in out JSON_Value_Type; Item : String)
   is
      A : JSON_Array := V.Get;
   begin
      Append (A, Create (Item));
      V := Create (A);
   end Append_Array;

   function Value_To_Array (V : JSON_Value_Type) return JSON_Array_Type is
   begin
      return GNATCOLL.JSON.Get (V);
   end Value_To_Array;

   function Array_Length (A : JSON_Array_Type) return Natural is
   begin
      return GNATCOLL.JSON.Length (A);
   end Array_Length;

   function Array_Item
     (A : JSON_Array_Type; I : Positive) return JSON_Value_Type
   is
   begin
      return GNATCOLL.JSON.Get (A, I);
   end Array_Item;

end Config.JSON_Parser;
