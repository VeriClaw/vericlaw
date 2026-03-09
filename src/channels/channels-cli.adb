with Ada.Text_IO;         use Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Agent.Context;       use type Agent.Context.Role;
with Agent.Loop_Pkg;
with Metrics;

package body Channels.CLI
  with SPARK_Mode => Off
is

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

            elsif Input'Length >= 6
              and then Input (Input'First .. Input'First + 4) = "/edit"
            then
               --  /edit N — fork at message N, prompt for replacement.
               declare
                  use Ada.Strings.Fixed;
                  Arg : constant String :=
                    Trim (Input (Input'First + 5 .. Input'Last),
                          Ada.Strings.Both);
                  N   : Positive;
               begin
                  N := Positive'Value (Arg);
                  if N > Conv.Msg_Count then
                     Put_Line ("Error: only"
                       & Natural'Image (Conv.Msg_Count) & " messages.");
                  else
                     declare
                        New_SID  : constant String :=
                          Agent.Context.Make_Session_ID;
                        Fork_OK  : Boolean;
                        Fork_Err : Unbounded_String;
                        Edit_Buf : String (1 .. 4096);
                        Edit_Last : Natural;
                     begin
                        --  Fork messages 1..N-1 into new session.
                        if N > 1 then
                           Memory.SQLite.Fork_Session
                             (Handle      => Mem,
                              Old_Session => To_String (Conv.Session_ID),
                              New_Session => New_SID,
                              Fork_At_Msg => N - 1,
                              Success     => Fork_OK,
                              Error       => Fork_Err);
                           if not Fork_OK then
                              Put_Line ("Fork failed: "
                                & To_String (Fork_Err));
                              goto Skip_Edit;
                           end if;
                        end if;

                        --  Build new conversation from forked messages.
                        declare
                           New_Conv : Agent.Context.Conversation;
                        begin
                           Set_Unbounded_String
                             (New_Conv.Session_ID, New_SID);
                           Set_Unbounded_String (New_Conv.Channel, "cli");
                           --  Copy messages 1..N-1 from old conv.
                           for I in 1 .. N - 1 loop
                              New_Conv.Msg_Count := New_Conv.Msg_Count + 1;
                              New_Conv.Messages (New_Conv.Msg_Count) :=
                                Conv.Messages (I);
                           end loop;

                           Put_Line ("Editing message"
                             & Positive'Image (N) & ":");
                           Put_Line ("  was: "
                             & To_String (Conv.Messages (N).Content));
                           Put ("  new> ");
                           begin
                              Get_Line (Edit_Buf, Edit_Last);
                           exception
                              when Ada.Text_IO.End_Error =>
                                 goto Skip_Edit;
                           end;

                           --  Append the replacement message and continue.
                           Agent.Context.Append_Message
                             (New_Conv,
                              Conv.Messages (N).Role,
                              Edit_Buf (1 .. Edit_Last),
                              Limit => Cfg.Memory.Max_History);

                           --  Save the replacement to DB.
                           Memory.SQLite.Save_Message
                             (Handle     => Mem,
                              Session_ID => New_SID,
                              Channel    => "cli",
                              Role       => Conv.Messages (N).Role,
                              Content    => Edit_Buf (1 .. Edit_Last));

                           --  Switch active conversation.
                           Conv := New_Conv;
                           Put_Line ("Branched to session "
                             & To_String (Conv.Session_ID));

                           --  If the edited message was a user message,
                           --  re-run the agent to get a new response.
                           if Conv.Messages (Conv.Msg_Count).Role =
                             Agent.Context.User
                           then
                              declare
                                 Reply : constant Agent.Loop_Pkg.Agent_Reply :=
                                   Agent.Loop_Pkg.Process_Message_Streaming
                                     (User_Input =>
                                        Edit_Buf (1 .. Edit_Last),
                                      Conv => Conv,
                                      Cfg  => Cfg,
                                      Mem  => Mem);
                              begin
                                 Metrics.Increment
                                   ("requests_total", "cli");
                                 New_Line;
                                 Put (Agent_Name);
                                 Flush;
                                 if Reply.Success then
                                    New_Line;
                                 else
                                    Metrics.Increment
                                      ("errors_total", "cli");
                                    Put_Line ("[Error] "
                                      & To_String (Reply.Error));
                                 end if;
                                 New_Line;
                              end;
                           end if;
                        end;
                     end;
                  end if;
                  <<Skip_Edit>>
               exception
                  when Constraint_Error =>
                     Put_Line ("Usage: /edit <message_number>");
               end;

            elsif Input = "/branch" then
               --  List all branches of the current session.
               declare
                  Br    : Agent.Context.Branch_Array;
                  Count : Natural;
               begin
                  Memory.SQLite.List_Branches
                    (Handle   => Mem,
                     Session  => To_String (Conv.Session_ID),
                     Branches => Br,
                     Count    => Count);
                  if Count = 0 then
                     Put_Line ("No branches for this session.");
                  else
                     Put_Line ("Branches (" & Natural'Image (Count) & "):");
                     for I in 1 .. Count loop
                        Put ("  " & To_String (Br (I).Session_ID));
                        Put (" (forked at msg"
                          & Natural'Image (Br (I).Fork_At) & ")");
                        if To_String (Br (I).Session_ID) =
                          To_String (Conv.Session_ID)
                        then
                           Put (" *current*");
                        end if;
                        New_Line;
                     end loop;
                  end if;
               end;

            elsif Input'Length >= 16
              and then Input (Input'First .. Input'First + 14) =
                "/branch switch "
            then
               --  /branch switch <id> — switch to a different branch.
               declare
                  use Ada.Strings.Fixed;
                  Target : constant String :=
                    Trim (Input (Input'First + 15 .. Input'Last),
                          Ada.Strings.Both);
                  New_Conv : Agent.Context.Conversation;
               begin
                  if Target'Length = 0 then
                     Put_Line ("Usage: /branch switch <session_id>");
                  else
                     Memory.SQLite.Load_History
                       (Handle     => Mem,
                        Session_ID => Target,
                        Max_Msgs   => Cfg.Memory.Max_History,
                        Conv       => New_Conv);
                     if New_Conv.Msg_Count = 0 then
                        Put_Line ("No messages found for session "
                          & Target);
                     else
                        Conv := New_Conv;
                        Set_Unbounded_String (Conv.Channel, "cli");
                        Put_Line ("Switched to session " & Target
                          & " (" & Natural'Image (Conv.Msg_Count)
                          & " messages)");
                     end if;
                  end if;
               end;

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
