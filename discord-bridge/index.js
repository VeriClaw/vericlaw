const { Client, GatewayIntentBits } = require('discord.js');
const express = require('express');

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ]
});

const messageQueue = [];
const seenIds = new Set();

client.on('messageCreate', (message) => {
  if (message.author.bot) return;
  if (!seenIds.has(message.id)) {
    seenIds.add(message.id);
    if (seenIds.size > 1000) {
      const first = seenIds.values().next().value;
      seenIds.delete(first);
    }
    messageQueue.push({
      id: message.id,
      from: message.author.id,
      username: message.author.username,
      channel_id: message.channel.id,
      guild_id: message.guild?.id || 'dm',
      content: message.content
    });
  }
});

client.login(process.env.DISCORD_BOT_TOKEN);

const api = express();
api.use(express.json());

api.get('/sessions/discord/messages', (req, res) => {
  const limit = parseInt(req.query.limit) || 10;
  res.json(messageQueue.splice(0, limit));
});

api.post('/sessions/discord/messages', async (req, res) => {
  const { channel_id, content, reply_to } = req.body;
  const channel = await client.channels.fetch(channel_id);
  const opts = { content };
  if (reply_to) opts.reply = { messageReference: reply_to };
  await channel.send(opts);
  res.json({ ok: true });
});

api.get('/health', (req, res) => res.json({ ok: true }));
api.listen(3002);
