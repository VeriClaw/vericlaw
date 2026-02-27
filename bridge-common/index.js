'use strict';

/**
 * Shared utilities for VeriClaw channel bridges.
 *
 * Usage in each bridge:
 *   const { createQueue, createBridgeApp, listen } = require('../bridge-common');
 *
 *   const q = createQueue();
 *   // push messages: q.tryPush(uniqueId, messageObject)
 *   const app = createBridgeApp('discord', q, async (body) => { ... });
 *   listen(app, 3002, 'Discord');
 */

const express = require('express');

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
 *   GET  /health                            — {ok: true}
 *
 * @param {string}   channel  Channel name (used in URL path, e.g. "discord")
 * @param {{ drain }} queue   Queue returned by createQueue()
 * @param {Function} sendFn  async (body) => void  Throws on send failure.
 * @returns {express.Application}
 */
function createBridgeApp(channel, queue, sendFn) {
  const app = express();
  app.use(express.json());

  app.get(`/sessions/${channel}/messages`, (req, res) => {
    res.json(queue.drain(req.query.limit));
  });

  app.post(`/sessions/${channel}/messages`, async (req, res) => {
    try {
      await sendFn(req.body || {});
      res.json({ ok: true });
    } catch (err) {
      console.error(`${channel}: send error:`, err.message);
      res.status(500).json({ error: err.message });
    }
  });

  app.get('/health', (_req, res) => res.json({ ok: true }));
  return app;
}

/**
 * Start the Express app on all interfaces and log the port.
 * @param {express.Application} app
 * @param {number}              port
 * @param {string}              name  Human-readable bridge name for the log line.
 */
function listen(app, port, name) {
  app.listen(port, '0.0.0.0', () =>
    console.log(`VeriClaw ${name} bridge listening on port ${port}`));
}

module.exports = { createQueue, createBridgeApp, listen };
