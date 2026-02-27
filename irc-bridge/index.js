const irc = require('irc-framework');
const express = require('express');

const client = new irc.Client();
client.connect({
  host: process.env.IRC_HOST || 'irc.libera.chat',
  port: parseInt(process.env.IRC_PORT || '6697'),
  tls: process.env.IRC_TLS !== 'false',
  nick: process.env.IRC_NICK || 'vericlaw',
  username: process.env.IRC_NICK || 'vericlaw',
  password: process.env.IRC_PASS,
});

const messageQueue = [];
const seenIds = new Set();

client.on('registered', () => {
  const channels = (process.env.IRC_CHANNELS || '#general').split(',');
  channels.forEach(ch => client.join(ch.trim()));
  console.log('Connected to IRC');
});

client.on('privmsg', (event) => {
  const id = `${event.nick}:${event.message}:${Date.now()}`;
  if (!seenIds.has(id)) {
    seenIds.add(id);
    messageQueue.push({ id, from: event.nick, channel: event.target, text: event.message });
  }
});

const api = express();
api.use(express.json());
api.get('/sessions/irc/messages', (req, res) => {
  const limit = parseInt(req.query.limit) || 10;
  res.json(messageQueue.splice(0, limit));
});
api.post('/sessions/irc/messages', (req, res) => {
  const { target, text } = req.body;
  client.say(target, text);
  res.json({ ok: true });
});
api.get('/health', (req, res) => res.json({ ok: true }));
api.listen(3005, () => console.log('IRC bridge listening on port 3005'));
