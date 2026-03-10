'use strict';

/**
 * VeriClaw Matrix Bridge
 *
 * Connects to a Matrix homeserver and exposes a REST API that
 * channels-matrix.adb polls.
 *
 * Env vars:
 *   MATRIX_HOMESERVER   Homeserver URL (default: https://matrix.org)
 *   MATRIX_TOKEN        Access token
 *   MATRIX_USER_ID      Full user ID (e.g. @bot:matrix.org)
 */

const sdk = require('matrix-js-sdk');
const { createQueue, createBridgeApp, listen } = require('../bridge-common');

const client = sdk.createClient({
  baseUrl:     process.env.MATRIX_HOMESERVER || 'https://matrix.org',
  accessToken: process.env.MATRIX_TOKEN,
  userId:      process.env.MATRIX_USER_ID,
});

const q = createQueue();
let ready = false;
let syncState = 'starting';
let lastError = null;

client.on('sync', (state, _prevState, _res, err) => {
  syncState = state;

  if (err) {
    lastError = err?.message || String(err);
  }

  if (state === 'PREPARED' || state === 'SYNCING' || state === 'CATCHUP') {
    ready = true;
    lastError = null;
    return;
  }

  if (state === 'ERROR' || state === 'RECONNECTING' || state === 'STOPPED') {
    ready = false;
  }
});

client.on('Room.timeline', (event) => {
  if (event.getType() !== 'm.room.message') return;
  const id = event.getId();
  q.tryPush(id, {
    id,
    from: event.getSender(),
    room: event.getRoomId(),
    text: event.getContent().body,
  });
});

client.startClient({ initialSyncLimit: 0 });

const app = createBridgeApp('matrix', q, async ({ room, text }) => {
  await client.sendTextMessage(room, text);
}, {
  readiness: () => ({
    ready,
    status: syncState,
    reason: ready ? undefined : (lastError || `matrix sync state: ${syncState}`),
  }),
});

listen(app, 3006, 'Matrix', {
  onShutdown: async () => {
    ready = false;
    client.stopClient();
  },
});
