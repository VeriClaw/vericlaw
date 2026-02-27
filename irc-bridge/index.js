'use strict';

/**
 * VeriClaw IRC Bridge
 *
 * Connects to an IRC server and exposes a REST API that channels-irc.adb polls.
 *
 * Env vars:
 *   IRC_HOST      IRC server hostname (default: irc.libera.chat)
 *   IRC_PORT      Port (default: 6697)
 *   IRC_TLS       "false" to disable TLS (default: true)
 *   IRC_NICK      Bot nickname (default: vericlaw)
 *   IRC_PASS      NickServ password (optional)
 *   IRC_CHANNELS  Comma-separated channel list (default: #general)
 */

const irc = require('irc-framework');
const { createQueue, createBridgeApp, listen } = require('../bridge-common');

const client = new irc.Client();
client.connect({
  host:     process.env.IRC_HOST || 'irc.libera.chat',
  port:     parseInt(process.env.IRC_PORT || '6697'),
  tls:      process.env.IRC_TLS !== 'false',
  nick:     process.env.IRC_NICK || 'vericlaw',
  username: process.env.IRC_NICK || 'vericlaw',
  password: process.env.IRC_PASS,
});

const q = createQueue();

client.on('registered', () => {
  const channels = (process.env.IRC_CHANNELS || '#general').split(',');
  channels.forEach(ch => client.join(ch.trim()));
  console.log('Connected to IRC');
});

client.on('privmsg', (event) => {
  const id = `${event.nick}:${event.target}:${Date.now()}`;
  q.tryPush(id, { id, from: event.nick, channel: event.target, text: event.message });
});

const app = createBridgeApp('irc', q, async ({ target, text }) => {
  client.say(target, text);
});

listen(app, 3005, 'IRC');

