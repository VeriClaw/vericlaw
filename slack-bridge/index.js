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
const {
  createBackoff,
  createQueue,
  createBridgeApp,
  listen,
} = require('../bridge-common');

const PORT = parseInt(process.env.PORT || '3001', 10);

const boltApp = new App({
  token:     process.env.SLACK_BOT_TOKEN,
  appToken:  process.env.SLACK_APP_TOKEN,
  socketMode: true,
});

const q = createQueue();
const startBackoff = createBackoff({
  initialMs: 1_000,
  maxMs: 30_000,
  factor: 2,
  jitterMs: 500,
});

let ready = false;
let lastError = null;
let startTimer;
let shuttingDown = false;

function clearStartRetry() {
  if (!startTimer) return;
  clearTimeout(startTimer);
  startTimer = undefined;
}

function scheduleStartRetry() {
  if (shuttingDown) return;

  clearStartRetry();
  const delayMs = startBackoff.fail();
  console.warn(`Retrying Slack Socket Mode startup in ${delayMs}ms`);
  startTimer = setTimeout(() => {
    startTimer = undefined;
    void startBoltApp();
  }, delayMs);
  startTimer.unref?.();
}

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

async function startBoltApp() {
  try {
    await boltApp.start();
    ready = true;
    lastError = null;
    startBackoff.reset();
    clearStartRetry();
    console.log('VeriClaw Slack bridge connected via Socket Mode');
  } catch (err) {
    ready = false;
    lastError = err?.message || String(err);
    console.error('Slack bridge failed to start:', lastError);
    if (typeof boltApp.stop === 'function') {
      try {
        await boltApp.stop();
      } catch {}
    }
    scheduleStartRetry();
  }
}

void startBoltApp();

const app = createBridgeApp('slack', q, async ({ channel, text, thread_ts }) => {
  if (!channel || !text) throw new Error('channel and text required');
  await boltApp.client.chat.postMessage({ channel, text, thread_ts });
}, {
  readiness: () => ({
    ready,
    status: ready ? 'connected' : 'connecting',
    reason: ready ? undefined : (lastError || 'slack socket mode not ready'),
  }),
});

listen(app, PORT, 'Slack', {
  onShutdown: async () => {
    shuttingDown = true;
    ready = false;
    clearStartRetry();
    if (typeof boltApp.stop === 'function') {
      await boltApp.stop();
    }
  },
});
