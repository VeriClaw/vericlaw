'use strict';

/**
 * VeriClaw Slack Bridge
 *
 * Connects to Slack via Socket Mode (no public URL required) and exposes
 * a REST API that channels-slack.adb polls.
 *
 * API:
 *   GET  /sessions/slack/messages?limit  -> [{id,from,channel,text,thread_ts}]
 *   POST /sessions/slack/messages        -> {channel,text,thread_ts} -> {ok:true}
 *   GET  /health                         -> {ok:true}
 *
 * Env vars:
 *   SLACK_BOT_TOKEN   Bot User OAuth Token (xoxb-...)
 *   SLACK_APP_TOKEN   App-Level Token for Socket Mode (xapp-...)
 *   PORT              REST API port (default 3001)
 */

const { App } = require('@slack/bolt');
const express = require('express');

const PORT = parseInt(process.env.PORT || '3001', 10);

const boltApp = new App({
  token: process.env.SLACK_BOT_TOKEN,
  appToken: process.env.SLACK_APP_TOKEN,
  socketMode: true,
});

// In-memory message queue drained by the Ada polling loop.
const messageQueue = [];
const seenIds = new Set();
const SEEN_LIMIT = 1000;

boltApp.message(async ({ message }) => {
  if (message.bot_id) return; // ignore bot messages
  if (!message.text) return;

  const id = `${message.channel}-${message.ts}`;
  if (seenIds.has(id)) return;

  seenIds.add(id);
  if (seenIds.size > SEEN_LIMIT) {
    // Evict the oldest entry.
    seenIds.delete(seenIds.values().next().value);
  }

  messageQueue.push({
    id,
    from: message.user,
    channel: message.channel,
    text: message.text,
    thread_ts: message.thread_ts || message.ts,
  });

  // Keep queue bounded.
  if (messageQueue.length > 500) messageQueue.shift();
});

// Connect to Slack via Socket Mode WebSocket.
(async () => {
  await boltApp.start();
  console.log('⚡️  VeriClaw Slack bridge connected via Socket Mode');
})();

// ─── REST API ────────────────────────────────────────────────────────────────

const api = express();
api.use(express.json());

// GET /sessions/slack/messages?limit=10
api.get('/sessions/slack/messages', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit || '10', 10), 100);
  const msgs = messageQueue.splice(0, limit);
  res.json(msgs);
});

// POST /sessions/slack/messages  {channel, text, thread_ts?}
api.post('/sessions/slack/messages', async (req, res) => {
  const { channel, text, thread_ts } = req.body || {};
  if (!channel || !text) {
    return res.status(400).json({ error: 'channel and text required' });
  }
  try {
    await boltApp.client.chat.postMessage({ channel, text, thread_ts });
    res.json({ ok: true });
  } catch (err) {
    console.error('postMessage error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

api.get('/health', (_req, res) => res.json({ ok: true }));

api.listen(PORT, '0.0.0.0', () => {
  console.log(`VeriClaw Slack bridge REST API listening on port ${PORT}`);
});
