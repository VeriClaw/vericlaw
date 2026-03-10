'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const { createQueue, createBridgeApp } = require('../bridge-common');

const CHANNEL = 'discord';
const q = createQueue();
let ready = true;
const app = createBridgeApp(CHANNEL, q, async (body) => {
  if (!body.channel_id || !body.content)
    throw new Error('channel_id and content required');
}, {
  readiness: () => ({ ready, reason: ready ? undefined : 'discord gateway not ready' }),
});

let server, base;

before(
  () =>
    new Promise((resolve) => {
      server = app.listen(0, '127.0.0.1', () => {
        base = `http://127.0.0.1:${server.address().port}`;
        resolve();
      });
    })
);

after(() => new Promise((resolve) => server.close(resolve)));

describe('discord-bridge', () => {
  it('GET /health returns 200', async () => {
    const res = await fetch(`${base}/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.ok, true);
  });

  it('GET /ready reflects readiness state', async () => {
    let res = await fetch(`${base}/ready`);
    assert.strictEqual(res.status, 200);

    ready = false;
    res = await fetch(`${base}/ready`);
    assert.strictEqual(res.status, 503);
    const body = await res.json();
    assert.strictEqual(body.ready, false);

    ready = true;
  });

  it('GET /sessions route returns 503 when bridge is not ready', async () => {
    ready = false;
    const res = await fetch(`${base}/sessions/${CHANNEL}/messages`);
    assert.strictEqual(res.status, 503);
    ready = true;
  });

  it('POST with missing fields returns 500', async () => {
    const res = await fetch(`${base}/sessions/${CHANNEL}/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 500);
    const body = await res.json();
    assert.ok(body.error);
  });

  it('malformed JSON returns 400', async () => {
    const res = await fetch(`${base}/sessions/${CHANNEL}/messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad json',
    });
    assert.strictEqual(res.status, 400);
  });
});
