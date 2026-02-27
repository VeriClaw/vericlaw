'use strict';

/**
 * VeriClaw Slack Bridge
 *
 * Connects to Slack via Socket Mode (no public URL required) and exposes
 * a REST API that channels-slack.adb polls.
 *
 * Env vars:
 *   SLACK_BOT_TOKEN   Bot User OAuth Token (xoxb-...)
 *   SLACK_APP_TOKEN   App-Level Token for Socket Mode (xapp-...)
 *   PORT              REST API port (default 3001)
 */

const { App } = require('@slack/bolt');
const { createQueue, createBridgeApp, listen } = require('../bridge-common');

const PORT = parseInt(process.env.PORT || '3001', 10);

const boltApp = new App({
  token:     process.env.SLACK_BOT_TOKEN,
  appToken:  process.env.SLACK_APP_TOKEN,
  socketMode: true,
});

const q = createQueue();

boltApp.message(async ({ message }) => {
  if (message.bot_id || !message.text) return;
  const id = `${message.channel}-${message.ts}`;
  q.tryPush(id, {
    id,
    from:      message.user,
    channel:   message.channel,
    text:      message.text,
    thread_ts: message.thread_ts || message.ts,
  });
});

(async () => {
  await boltApp.start();
  console.log('VeriClaw Slack bridge connected via Socket Mode');
})();

const app = createBridgeApp('slack', q, async ({ channel, text, thread_ts }) => {
  if (!channel || !text) throw new Error('channel and text required');
  await boltApp.client.chat.postMessage({ channel, text, thread_ts });
});

listen(app, PORT, 'Slack');

