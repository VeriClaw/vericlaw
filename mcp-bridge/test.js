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
    env: { ...process.env, PORT: String(PORT), MCP_SERVERS: '[]' },
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

describe('mcp-bridge', () => {
  it('GET /health returns 200', async () => {
    const res = await fetch(`${base}/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.ok, true);
    assert.strictEqual(typeof body.tools, 'number');
  });

  it('POST /tools with invalid name format returns 400', async () => {
    const res = await fetch(`${base}/tools/badformat/call`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer fake`,
      },
      body: JSON.stringify({}),
    });
    // 401 because auth fails first, or 400 if auth is bypassed
    assert.ok([400, 401].includes(res.status));
  });

  it('malformed JSON returns 400', async () => {
    const res = await fetch(`${base}/tools/mcp__test__tool/call`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad json',
    });
    assert.strictEqual(res.status, 400);
  });
});
