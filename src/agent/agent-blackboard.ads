--  Blackboard pattern for inter-agent communication.
--  Sub-agents write findings; parent agents read them.
--  Thread-safe via a protected object with a bounded key-value store.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

pragma SPARK_Mode (Off);
package Agent.Blackboard is

   Max_Entries : constant := 64;

   procedure Put (Key : String; Value : String);
   --  Insert or update an entry.  Oldest entry is evicted when full.

   function Get (Key : String) return String;
   --  Returns the value for Key, or "" if not present.

   function Has (Key : String) return Boolean;
   --  Returns True if Key exists in the blackboard.

   procedure Clear;
   --  Remove all entries.

end Agent.Blackboard;
