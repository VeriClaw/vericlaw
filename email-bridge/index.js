'use strict';

/**
 * VeriClaw Email Bridge
 *
 * Polls an IMAP inbox for unread messages and sends replies via SMTP.
 * Exposes a REST API that channels-email.adb polls.
 *
 * Env vars:
 *   EMAIL_USER    IMAP/SMTP username
 *   EMAIL_PASS    IMAP/SMTP password (or App Password for Gmail)
 *   IMAP_HOST     IMAP host (default: imap.gmail.com)
 *   IMAP_PORT     IMAP port (default: 993)
 *   SMTP_HOST     SMTP host (default: smtp.gmail.com)
 *   SMTP_PORT     SMTP port (default: 587; use 465 for SSL)
 */

const imaps = require('imap-simple');
const nodemailer = require('nodemailer');
const { simpleParser } = require('mailparser');
const {
  createBackoff,
  createQueue,
  createBridgeApp,
  listen,
} = require('../bridge-common');

const IMAP_CONFIG = {
  imap: {
    user:        process.env.EMAIL_USER,
    password:    process.env.EMAIL_PASS,
    host:        process.env.IMAP_HOST || 'imap.gmail.com',
    port:        parseInt(process.env.IMAP_PORT || '993'),
    tls:         true,
    authTimeout: 10000,
  },
};

const transporter = nodemailer.createTransport({
  host:   process.env.SMTP_HOST || 'smtp.gmail.com',
  port:   parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_PORT === '465',
  auth:   { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
});

const q = createQueue();
const POLL_INTERVAL_MS = 30_000;
const POLL_STALE_AFTER_MS = POLL_INTERVAL_MS * 4;
const pollBackoff = createBackoff({
  initialMs: POLL_INTERVAL_MS,
  maxMs: POLL_INTERVAL_MS * 8,
  factor: 2,
  jitterMs: 1_000,
});

let pollTimer;
let shuttingDown = false;
let lastSuccessAt = 0;
let lastError = 'awaiting first successful inbox poll';

function schedulePoll(delayMs) {
  if (shuttingDown) return;
  clearTimeout(pollTimer);
  pollTimer = setTimeout(() => {
    pollTimer = undefined;
    void pollInbox();
  }, delayMs);
  pollTimer.unref?.();
}

function readiness() {
  const ready = lastSuccessAt > 0 && (Date.now() - lastSuccessAt) <= POLL_STALE_AFTER_MS;
  return {
    ready,
    status: ready ? 'connected' : 'degraded',
    reason: ready ? undefined : lastError,
  };
}

async function pollInbox() {
  let conn;

  try {
    conn = await imaps.connect(IMAP_CONFIG);
    await conn.openBox('INBOX');
    const msgs = await conn.search(['UNSEEN'], { bodies: [''], markSeen: true });
    for (const msg of msgs) {
      const all = msg.parts.find(p => p.which === '');
      if (!all) continue;
      const parsed = await simpleParser(all.body);
      const id = parsed.messageId || `${Date.now()}-${Math.random()}`;
      q.tryPush(id, {
        id,
        from:    parsed.from?.value?.[0]?.address || '',
        subject: parsed.subject || '',
        text:    parsed.text || '',
      });
    }

    lastSuccessAt = Date.now();
    lastError = null;
    pollBackoff.reset();
    schedulePoll(POLL_INTERVAL_MS);
  } catch (e) {
    lastError = `imap poll error: ${e?.message || String(e)}`;
    const delayMs = pollBackoff.fail();
    console.error(`IMAP poll error (retrying in ${delayMs}ms):`, e?.message || String(e));
    schedulePoll(delayMs);
  } finally {
    if (conn) {
      try {
        conn.end();
      } catch {}
    }
  }
}

schedulePoll(0);

const app = createBridgeApp('email', q, async ({ to, subject, text }) => {
  await transporter.sendMail({ from: process.env.EMAIL_USER, to, subject, text });
}, {
  readiness,
});

listen(app, 3003, 'Email', {
  onShutdown: async () => {
    shuttingDown = true;
    clearTimeout(pollTimer);
  },
});
