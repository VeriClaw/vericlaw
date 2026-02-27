with Ada.Text_IO;         use Ada.Text_IO;
with Agent.Context;
with Agent.Loop_Pkg;
with Metrics;

pragma SPARK_Mode (Off);
package body Channels.CLI is

   Prompt     : constant String := "you> ";
   Agent_Name : constant String := "vericlaw> ";

   procedure Run_Interactive
     (Cfg : Config.Schema.Agent_Config;
      Mem : Memory.SQLite.Memory_Handle)
   is
      Conv : Agent.Context.Conversation;
      Line : String (1 .. 4096);
      Last : Natural;
   begin
      Set_Unbounded_String (Conv.Session_ID, Agent.Context.Make_Session_ID);
      Set_Unbounded_String (Conv.Channel, "cli");

      Put_Line ("VeriClaw v1.0  |  type 'exit' to quit");
      Put_Line ("Provider: " & To_String (Cfg.Providers (1).Model));
      New_Line;

      loop
         Put (Prompt);
         begin
            Get_Line (Line, Last);
         exception
            when Ada.Text_IO.End_Error => exit;
         end;

         declare
            Input : constant String := Line (1 .. Last);
         begin
            exit when Input = "exit" or else Input = "quit"
              or else Input = "/exit" or else Input = "/quit";

            if Input'Length = 0 then
               null;  -- skip empty lines

            elsif Input = "/clear" then
               Conv.Msg_Count := 0;
               Put_Line ("Conversation cleared.");

            elsif Input = "/memory" then
               Put_Line ("Session: " & To_String (Conv.Session_ID));
               Put_Line ("Messages: " & Natural'Image (Conv.Msg_Count));

            else
               declare
                  Reply : constant Agent.Loop_Pkg.Agent_Reply :=
                    Agent.Loop_Pkg.Process_Message_Streaming
                      (User_Input => Input,
                       Conv       => Conv,
                       Cfg        => Cfg,
                       Mem        => Mem);
               begin
                  Metrics.Increment ("requests_total", "cli");
                  New_Line;
                  Put (Agent_Name);
                  Flush;
                  --  Tokens were already streamed to stdout by Chat_Streaming.
                  --  Print trailing newline; on error show the message.
                  if Reply.Success then
                     New_Line;
                  else
                     Metrics.Increment ("errors_total", "cli");
                     Put_Line ("[Error] " & To_String (Reply.Error));
                  end if;
                  New_Line;
               end;
            end if;
         end;
      end loop;

      New_Line;
      Put_Line ("Goodbye.");
   end Run_Interactive;

   procedure Run_Once
     (Input : String;
      Cfg   : Config.Schema.Agent_Config;
      Mem   : Memory.SQLite.Memory_Handle)
   is
      Conv  : Agent.Context.Conversation;
      Reply : Agent.Loop_Pkg.Agent_Reply;
   begin
      Set_Unbounded_String (Conv.Session_ID, Agent.Context.Make_Session_ID);
      Set_Unbounded_String (Conv.Channel, "cli");

      Reply := Agent.Loop_Pkg.Process_Message_Streaming
        (User_Input => Input,
         Conv       => Conv,
         Cfg        => Cfg,
         Mem        => Mem);

      Metrics.Increment ("requests_total", "cli");

      --  Tokens were already streamed; print newline and any error.
      New_Line;
      if not Reply.Success then
         Put_Line ("Error: " & To_String (Reply.Error));
      end if;
   end Run_Once;

end Channels.CLI;
