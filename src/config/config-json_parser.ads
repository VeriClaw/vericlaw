--  Pure-Ada JSON parser for VeriClaw — zero external dependencies.
--  Provides safe accessors that return defaults instead of raising
--  exceptions on missing/wrong-type keys.
--
--  The JSON_Value_Type and JSON_Array_Type are opaque handles backed by a
--  heap-allocated node tree (Taft Amendment type completed in the body).

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Config.JSON_Parser
  with SPARK_Mode => Off
is

   --  Opaque JSON value and array handles.
   type JSON_Value_Type is private;
   type JSON_Array_Type is private;

   --  Parse a JSON string. Returns (Valid => False) on parse error.
   type Parse_Result is record
      Valid : Boolean        := False;
      Root  : JSON_Value_Type;
      Error : Unbounded_String;
   end record;

   function Parse (Source : String) return Parse_Result;

   --  Safe field accessors — return defaults on missing/wrong type.
   function Get_String
     (V       : JSON_Value_Type;
      Key     : String;
      Default : String := "") return String;

   function Get_Integer
     (V       : JSON_Value_Type;
      Key     : String;
      Default : Integer := 0) return Integer;

   function Get_Boolean
     (V       : JSON_Value_Type;
      Key     : String;
      Default : Boolean := False) return Boolean;

   function Get_Object
     (V   : JSON_Value_Type;
      Key : String) return JSON_Value_Type;

   function Has_Key
     (V   : JSON_Value_Type;
      Key : String) return Boolean;

   --  Array helpers.
   function Value_To_Array (V : JSON_Value_Type) return JSON_Array_Type;
   function Array_Length    (A : JSON_Array_Type) return Natural;
   function Array_Item      (A : JSON_Array_Type; I : Positive)
                             return JSON_Value_Type;

   --  Serialisation
   function To_JSON_String     (V : JSON_Value_Type) return String;

   --  Escape a plain string as a JSON string literal (with surrounding quotes).
   function Escape_JSON_String (S : String) return String;

   --  Build helpers
   function Build_Object return JSON_Value_Type;
   function Build_Array  return JSON_Value_Type;

   procedure Set_Field (V : in out JSON_Value_Type; Key : String; Value : String);
   procedure Set_Field (V : in out JSON_Value_Type; Key : String; Value : Integer);
   procedure Set_Field (V : in out JSON_Value_Type; Key : String; Value : Boolean);
   procedure Set_Field (V : in out JSON_Value_Type; Key : String;
                        Value : JSON_Value_Type);

   procedure Append_Array (V : in out JSON_Value_Type; Item : JSON_Value_Type);
   procedure Append_Array (V : in out JSON_Value_Type; Item : String);

private

   --  Taft Amendment: JSON_Node is completed in the package body.
   type JSON_Node;
   type JSON_Node_Ptr is access JSON_Node;

   type JSON_Value_Type is record
      Ptr : JSON_Node_Ptr := null;
   end record;

   type JSON_Array_Type is record
      Ptr : JSON_Node_Ptr := null;
   end record;

end Config.JSON_Parser;
