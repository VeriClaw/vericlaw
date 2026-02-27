'use strict';

/**
 * VeriClaw WhatsApp Bridge
 *
 * A lightweight Express REST server wrapping @whiskeysockets/baileys.
 * Exposes the REST API that channels-whatsapp.adb polls.
 *
 * API:
 *   GET  /sessions/:name/status          -> {status: "open"|"connecting"|"close"}
 *   POST /sessions/:name/pair            -> {phone} -> {code: "ABCD-1234"}
 *   GET  /sessions/:name/messages?limit  -> [{id,from,body,fromMe,timestamp}]
 *   POST /sessions/:name/messages        -> {chatId,message} -> {ok:true}
 *
 * Env vars:
 *   PORT          HTTP port (default 3000)
 *   WA_SESSION    Session name (default "vericlaw")
 *   WA_PHONE      Phone number for automatic pairing on startup (e.g. +1234567890)
 *   SESSIONS_DIR  Where to persist auth state (default ./sessions)
 */

const express = require('express');
const path = require('path');
const fs = require('fs');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
} = require('@whiskeysockets/baileys');
const pino = require('pino');

const PORT = parseInt(process.env.PORT || '3000', 10);
const DEFAULT_SESSION = process.env.WA_SESSION || 'vericlaw';
const SESSIONS_DIR = process.env.SESSIONS_DIR || path.join(__dirname, 'sessions');
const AUTO_PHONE = process.env.WA_PHONE || '';

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });

// In-memory message buffer per session: [{id,from,body,fromMe,timestamp}]
const messageQueues = {};
// Track last N message IDs to prevent re-delivery (circular buffer per session)
const seenIds = {};
const SEEN_LIMIT = 200;

function markSeen(session, id) {
  if (!seenIds[session]) seenIds[session] = [];
  seenIds[session].push(id);
  if (seenIds[session].length > SEEN_LIMIT) seenIds[session].shift();
}
function wasSeen(session, id) {
  return seenIds[session] && seenIds[session].includes(id);
}

// Active socket + state per session
const sockets = {};
const sessionStatus = {}; // "connecting" | "open" | "close"
const pairingCodeResolvers = {}; // pending pair() Promises

async function createSession(name) {
  const authDir = path.join(SESSIONS_DIR, name);
  fs.mkdirSync(authDir, { recursive: true });

  const { state, saveCreds } = await useMultiFileAuthState(authDir);
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    version,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, pino({ level: 'silent' })),
    },
    logger: pino({ level: 'silent' }),
    printQRInTerminal: false, // disable QR — we use pairing codes
    browser: ['VeriClaw', 'Desktop', '1.0.0'],
  });

  sockets[name] = sock;
  sessionStatus[name] = 'connecting';
  messageQueues[name] = messageQueues[name] || [];

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      // QR generated — if we have a phone number waiting, request pairing code instead
      const phone = AUTO_PHONE || (pairingCodeResolvers[name] && pairingCodeResolvers[name].phone);
      if (phone) {
        try {
          const normalized = phone.replace(/[^0-9]/g, '');
          const code = await sock.requestPairingCode(normalized);
          const formatted = code.match(/.{1,4}/g).join('-');
          logger.info({ session: name, code: formatted },
            `WhatsApp pairing code: ${formatted} — enter in WhatsApp > Settings > Linked Devices > Link with phone number`);
          process.stdout.write(`\nWhatsApp pairing code: ${formatted}\nEnter this in WhatsApp > Settings > Linked Devices > "Link with phone number"\n\n`);
          if (pairingCodeResolvers[name]) {
            pairingCodeResolvers[name].resolve({ code: formatted });
            delete pairingCodeResolvers[name];
          }
        } catch (err) {
          logger.error({ err }, 'Failed to request pairing code');
          if (pairingCodeResolvers[name]) {
            pairingCodeResolvers[name].reject(err);
            delete pairingCodeResolvers[name];
          }
        }
      } else {
        logger.warn({ session: name },
          'QR code generated but WA_PHONE not set. Set WA_PHONE or call POST /sessions/:name/pair');
      }
    }

    if (connection === 'open') {
      sessionStatus[name] = 'open';
      logger.info({ session: name }, 'WhatsApp session open');
    } else if (connection === 'close') {
      sessionStatus[name] = 'close';
      const code = lastDisconnect?.error?.output?.statusCode;
      const shouldReconnect = code !== DisconnectReason.loggedOut;
      logger.info({ session: name, code, shouldReconnect }, 'Connection closed');
      if (shouldReconnect) {
        setTimeout(() => createSession(name), 5000);
      } else {
        logger.warn({ session: name }, 'Logged out — delete session dir to re-pair');
      }
    }
  });

  sock.ev.on('messages.upsert', ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const msg of messages) {
      const id = msg.key.id;
      if (wasSeen(name, id)) continue;
      markSeen(name, id);

      const from = msg.key.remoteJid;
      const fromMe = msg.key.fromMe || false;
      const body =
        msg.message?.conversation ||
        msg.message?.extendedTextMessage?.text ||
        msg.message?.imageMessage?.caption ||
        '';
      const timestamp = msg.messageTimestamp || Math.floor(Date.now() / 1000);

      messageQueues[name].push({ id, from, body, fromMe, timestamp });
      // Keep buffer bounded
      if (messageQueues[name].length > 500) messageQueues[name].shift();
    }
  });

  return sock;
}

// Start default session on boot
createSession(DEFAULT_SESSION).catch((err) =>
  logger.error({ err }, 'Failed to create default session'));

// ─── Express ────────────────────────────────────────────────────────────────

const app = express();
app.use(express.json());

// GET /sessions/:name/status
app.get('/sessions/:name/status', (req, res) => {
  const { name } = req.params;
  res.json({ status: sessionStatus[name] || 'close' });
});

// POST /sessions/:name/pair  {phone: "+1234567890"}
app.post('/sessions/:name/pair', async (req, res) => {
  const { name } = req.params;
  const { phone } = req.body || {};
  if (!phone) return res.status(400).json({ error: 'phone required' });

  // If session is already open, nothing to do
  if (sessionStatus[name] === 'open') {
    return res.json({ status: 'already_open' });
  }

  // Store resolver; the connection.update handler will call it when QR fires
  const promise = new Promise((resolve, reject) => {
    pairingCodeResolvers[name] = { phone, resolve, reject };
  });

  // If socket not yet created, create it now
  if (!sockets[name]) {
    createSession(name).catch(reject => logger.error({ reject }, 'session error'));
  }

  try {
    const result = await Promise.race([
      promise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 60_000)),
    ]);
    res.json(result);
  } catch (err) {
    delete pairingCodeResolvers[name];
    res.status(504).json({ error: err.message });
  }
});

// GET /sessions/:name/messages?limit=10
app.get('/sessions/:name/messages', (req, res) => {
  const { name } = req.params;
  const limit = Math.min(parseInt(req.query.limit || '10', 10), 100);
  const queue = messageQueues[name] || [];
  // Return and drain
  const msgs = queue.splice(0, limit);
  res.json(msgs);
});

// POST /sessions/:name/messages  {chatId, message}
app.post('/sessions/:name/messages', async (req, res) => {
  const { name } = req.params;
  const { chatId, message } = req.body || {};
  if (!chatId || !message) return res.status(400).json({ error: 'chatId and message required' });

  const sock = sockets[name];
  if (!sock || sessionStatus[name] !== 'open') {
    return res.status(503).json({ error: 'session not open' });
  }

  try {
    await sock.sendMessage(chatId, { text: message });
    res.json({ ok: true });
  } catch (err) {
    logger.error({ err, chatId }, 'sendMessage failed');
    res.status(500).json({ error: err.message });
  }
});

app.get('/health', (_req, res) => res.json({ ok: true }));

app.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT }, 'VeriClaw WhatsApp bridge listening');
  if (AUTO_PHONE) {
    logger.info({ phone: AUTO_PHONE }, 'Auto-pairing enabled via WA_PHONE');
  }
});
