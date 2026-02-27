'use strict';

/**
 * VeriClaw Discord Bridge
 *
 * Connects to Discord via Gateway WebSocket and exposes a REST API
 * that channels-discord.adb polls.
 *
 * Env vars:
 *   DISCORD_BOT_TOKEN   Discord bot token
 */

const { Client, GatewayIntentBits } = require('discord.js');
const { createQueue, createBridgeApp, listen } = require('../bridge-common');

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ],
});

const q = createQueue();

client.on('messageCreate', (message) => {
  if (message.author.bot) return;
  q.tryPush(message.id, {
    id:         message.id,
    from:       message.author.id,
    username:   message.author.username,
    channel_id: message.channel.id,
    guild_id:   message.guild?.id || 'dm',
    content:    message.content,
  });
});

client.login(process.env.DISCORD_BOT_TOKEN);

const app = createBridgeApp('discord', q, async ({ channel_id, content, reply_to }) => {
  const ch = await client.channels.fetch(channel_id);
  const opts = { content };
  if (reply_to) opts.reply = { messageReference: reply_to };
  await ch.send(opts);
});

listen(app, 3002, 'Discord');

