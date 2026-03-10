'use strict';

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const { spawn } = require('node:child_process');

const PORT = 10000 + Math.floor(Math.random() * 50000);
let proc, base;

async function waitForServer(url, timeoutMs = 10000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url);
      if (res.ok) return;
    } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('Server did not start in time');
}

before(async () => {
  base = `http://127.0.0.1:${PORT}`;
  proc = spawn('node', ['index.js'], {
    env: { ...process.env, PORT: String(PORT) },
    cwd: __dirname,
    stdio: 'pipe',
  });
  proc.stderr.on('data', () => {});
  proc.stdout.on('data', () => {});
  await waitForServer(`${base}/health`);
});

after(() => {
  if (proc) proc.kill();
});

describe('browser-bridge', () => {
  it('GET /health returns 200', async () => {
    const res = await fetch(`${base}/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.ok, true);
  });

  it('POST /browse without url returns 400', async () => {
    const res = await fetch(`${base}/browse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 400);
    const body = await res.json();
    assert.strictEqual(body.ok, false);
  });

  it('malformed JSON returns 400', async () => {
    const res = await fetch(`${base}/browse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad json',
    });
    assert.strictEqual(res.status, 400);
  });
});
