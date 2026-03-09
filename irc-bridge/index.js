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
let ready = false;
let lastError = null;

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
  ready = true;
  lastError = null;
  const channels = (process.env.IRC_CHANNELS || '#general').split(',');
  channels.forEach(ch => client.join(ch.trim()));
  console.log('Connected to IRC');
});

for (const eventName of ['close', 'disconnected']) {
  client.on(eventName, () => {
    ready = false;
    lastError = `irc event: ${eventName}`;
    console.warn(`IRC bridge connection event: ${eventName}`);
  });
}

client.on('error', (err) => {
  ready = false;
  lastError = err?.message || String(err);
  console.error('IRC client error:', lastError);
});

client.on('privmsg', (event) => {
  const id = `${event.nick}:${event.target}:${Date.now()}`;
  q.tryPush(id, { id, from: event.nick, channel: event.target, text: event.message });
});

const app = createBridgeApp('irc', q, async ({ target, text }) => {
  client.say(target, text);
}, {
  readiness: () => ({
    ready,
    status: ready ? 'connected' : 'connecting',
    reason: ready ? undefined : (lastError || 'irc connection not ready'),
  }),
});

listen(app, 3005, 'IRC', {
  onShutdown: async () => {
    ready = false;
    if (typeof client.quit === 'function') {
      client.quit('VeriClaw bridge shutting down');
    }
  },
});
