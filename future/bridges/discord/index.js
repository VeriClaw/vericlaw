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
const {
  createBackoff,
  createQueue,
  createBridgeApp,
  listen,
} = require('../bridge-common');

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
    GatewayIntentBits.DirectMessages,
  ],
});

const q = createQueue();
const loginBackoff = createBackoff({
  initialMs: 1_000,
  maxMs: 30_000,
  factor: 2,
  jitterMs: 500,
});

let lastError = null;
let loginTimer;
let shuttingDown = false;

function clearLoginRetry() {
  if (!loginTimer) return;
  clearTimeout(loginTimer);
  loginTimer = undefined;
}

function scheduleLoginRetry() {
  if (shuttingDown) return;

  clearLoginRetry();
  const delayMs = loginBackoff.fail();
  console.warn(`Retrying Discord login in ${delayMs}ms`);
  loginTimer = setTimeout(() => {
    loginTimer = undefined;
    void loginClient();
  }, delayMs);
  loginTimer.unref?.();
}

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

client.on('ready', () => {
  lastError = null;
  loginBackoff.reset();
  clearLoginRetry();
  console.log(`VeriClaw Discord bridge connected as ${client.user?.tag || 'unknown-user'}`);
});

client.on('shardReady', (shardId) => {
  lastError = null;
  console.log(`Discord shard ${shardId} ready`);
});

client.on('shardDisconnect', (_event, shardId) => {
  lastError = `discord shard ${shardId} disconnected`;
  console.warn(lastError);
});

client.on('error', (err) => {
  lastError = err?.message || String(err);
  console.error('Discord client error:', lastError);
});

async function loginClient() {
  try {
    await client.login(process.env.DISCORD_BOT_TOKEN);
  } catch (err) {
    lastError = err?.message || String(err);
    console.error('Discord login failed:', lastError);
    try {
      client.destroy();
    } catch {}
    scheduleLoginRetry();
  }
}

void loginClient();

const app = createBridgeApp('discord', q, async ({ channel_id, content, reply_to }) => {
  const ch = await client.channels.fetch(channel_id);
  const opts = { content };
  if (reply_to) opts.reply = { messageReference: reply_to };
  await ch.send(opts);
}, {
  readiness: () => ({
    ready: client.isReady(),
    status: client.isReady() ? 'connected' : 'connecting',
    reason: client.isReady() ? undefined : (lastError || 'discord gateway not ready'),
  }),
});

listen(app, 3002, 'Discord', {
  onShutdown: async () => {
    shuttingDown = true;
    clearLoginRetry();
    client.destroy();
  },
});
