'use strict';

/**
 * Shared utilities for VeriClaw channel bridges.
 *
 * Usage in each bridge:
 *   const { createQueue, createBridgeApp, listen } = require('../bridge-common');
 *
 *   const q = createQueue();
 *   // push messages: q.tryPush(uniqueId, messageObject)
 *   const app = createBridgeApp('discord', q, async (body) => { ... }, {
 *     readiness: () => ({ ready: client.isReady() }),
 *   });
 *   listen(app, 3002, 'Discord', { onShutdown: async () => client.destroy() });
 */

const express = require('express');

function resolveReadiness(readiness) {
  const raw = typeof readiness === 'function' ? readiness() : readiness;

  if (raw === undefined || raw === null) return { ready: true };
  if (typeof raw === 'boolean') return { ready: raw };

  return { ready: raw.ready !== false, ...raw };
}

function buildReadyResponse(readiness, ok) {
  const { ready, ...rest } = resolveReadiness(readiness);
  return { ok, ready, ...rest };
}

function addHealthRoutes(app, readiness) {
  app.get('/health', (_req, res) =>
    res.json(buildReadyResponse(readiness, true)));

  app.get('/ready', (_req, res) => {
    const state = resolveReadiness(readiness);
    const response = { ok: state.ready, ...state };
    res.status(response.ready ? 200 : 503).json(response);
  });
}

function requireReady(res, readiness) {
  const state = resolveReadiness(readiness);
  if (state.ready) return true;

  res.status(503).json({
    error: state.reason || 'bridge not ready',
    ready: false,
    status: state.status,
  });
  return false;
}

/**
 * Create a bounded message queue with built-in dedup.
 * @param {number} maxQueue  Max messages to buffer before dropping oldest (default 500).
 * @param {number} maxSeen   Max unique IDs to track for dedup (default 1000).
 * @returns {{ tryPush, drain }}
 */
function createQueue(maxQueue = 500, maxSeen = 1000) {
  const queue = [];
  const seen = new Set();

  return {
    /**
     * Add msg to queue if id has not been seen before.
     * @returns {boolean} true if the message was added.
     */
    tryPush(id, msg) {
      if (seen.has(id)) return false;
      seen.add(id);
      if (seen.size > maxSeen) seen.delete(seen.values().next().value);
      queue.push(msg);
      if (queue.length > maxQueue) queue.shift();
      return true;
    },

    /**
     * Remove and return up to `limit` messages (max 100).
     */
    drain(limit = 10) {
      return queue.splice(0, Math.min(parseInt(limit, 10) || 10, 100));
    },
  };
}

/**
 * Create an Express app with standard channel bridge routes.
 *
 * Routes added:
 *   GET  /sessions/:channel/messages?limit  — drain queue and return JSON array
 *   POST /sessions/:channel/messages        — call sendFn(body); throws on error
 *   GET  /health                            — {ok: true, ready: boolean}
 *   GET  /ready                             — readiness probe (200/503)
 *
 * @param {string}   channel  Channel name (used in URL path, e.g. "discord")
 * @param {{ drain }} queue   Queue returned by createQueue()
 * @param {Function} sendFn  async (body) => void  Throws on send failure.
 * @param {object}   options
 * @returns {express.Application}
 */
function createBridgeApp(channel, queue, sendFn, options = {}) {
  const app = express();
  app.use(express.json());

  app.get(`/sessions/${channel}/messages`, (req, res) => {
    if (options.requireReady !== false && !requireReady(res, options.readiness)) {
      return;
    }
    res.json(queue.drain(req.query.limit));
  });

  app.post(`/sessions/${channel}/messages`, async (req, res) => {
    if (options.requireReady !== false && !requireReady(res, options.readiness)) {
      return;
    }

    try {
      await sendFn(req.body || {});
      res.json({ ok: true });
    } catch (err) {
      console.error(`${channel}: send error:`, err.message);
      res.status(500).json({ error: err.message });
    }
  });

  addHealthRoutes(app, options.readiness);
  return app;
}

/**
 * Start the Express app on all interfaces and log the port.
 * @param {express.Application} app
 * @param {number}              port
 * @param {string}              name  Human-readable bridge name for the log line.
 */
function listen(app, port, name, options = {}) {
  const host = options.host || '0.0.0.0';
  const shutdownTimeoutMs = options.shutdownTimeoutMs || 10_000;
  let shuttingDown = false;

  const server = app.listen(port, host, () =>
    console.log(`VeriClaw ${name} bridge listening on ${host}:${port}`));

  async function shutdown(signal) {
    if (shuttingDown) return;
    shuttingDown = true;

    console.log(`VeriClaw ${name} bridge shutting down on ${signal}`);
    const forceExit = setTimeout(() => {
      console.error(`VeriClaw ${name} bridge shutdown timed out`);
      process.exit(1);
    }, shutdownTimeoutMs);
    forceExit.unref?.();

    let exitCode = 0;

    try {
      if (typeof options.onShutdown === 'function') {
        await options.onShutdown(signal);
      }
    } catch (err) {
      exitCode = 1;
      console.error(`${name}: shutdown error:`, err.message);
    }

    server.close((err) => {
      clearTimeout(forceExit);
      if (err) {
        exitCode = 1;
        console.error(`${name}: server close error:`, err.message);
      }
      process.exit(exitCode);
    });
  }

  process.once('SIGTERM', () => void shutdown('SIGTERM'));
  process.once('SIGINT', () => void shutdown('SIGINT'));

  return server;
}

function createBackoff(options = {}) {
  const initialMs = options.initialMs || 1_000;
  const maxMs = options.maxMs || 30_000;
  const factor = options.factor || 2;
  const jitterMs = options.jitterMs || 0;
  let nextMs = initialMs;

  return {
    reset() {
      nextMs = initialMs;
    },

    fail() {
      const jitter = jitterMs > 0 ? Math.floor(Math.random() * jitterMs) : 0;
      const delayMs = nextMs + jitter;
      nextMs = Math.min(maxMs, Math.max(initialMs, Math.round(nextMs * factor)));
      return delayMs;
    },
  };
}

module.exports = {
  addHealthRoutes,
  createBackoff,
  createQueue,
  createBridgeApp,
  listen,
};
