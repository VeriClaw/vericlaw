--  Brave Search API tool.
--  Uses HTTP.Client (libcurl) for the REST call.
--  Returns structured results as JSON for the agent.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Tools.Brave_Search is

   type Search_Result is record
      Title   : Unbounded_String;
      URL     : Unbounded_String;
      Snippet : Unbounded_String;
   end record;

   Max_Results : constant := 10;
   type Search_Results is array (Positive range <>) of Search_Result;

   type Brave_Result is record
      Success : Boolean := False;
      Results : Search_Results (1 .. Max_Results);
      Count   : Natural := 0;
      Error   : Unbounded_String;
   end record;

   function Search
     (Query        : String;
      API_Key      : String;
      Num_Results  : Positive := 5) return Brave_Result;

   function To_Agent_Text (R : Brave_Result) return String;
   --  Format results as readable text for the agent's context.

end Tools.Brave_Search;
