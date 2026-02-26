--  CLI channel: interactive readline mode + one-shot mode.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Config.Schema;
with Memory.SQLite;

package Channels.CLI is

   --  Run interactive chat loop until EOF or "exit"/"quit".
   procedure Run_Interactive
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle);

   --  Process a single user input and print the response.
   procedure Run_Once
     (Input : String;
      Cfg   : Config.Schema.Agent_Config;
      Mem   : Memory.SQLite.Memory_Handle);

end Channels.CLI;
