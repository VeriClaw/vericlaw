const imaps = require('imap-simple');
const nodemailer = require('nodemailer');
const { simpleParser } = require('mailparser');
const express = require('express');

const IMAP_CONFIG = {
  imap: {
    user: process.env.EMAIL_USER,
    password: process.env.EMAIL_PASS,
    host: process.env.IMAP_HOST || 'imap.gmail.com',
    port: parseInt(process.env.IMAP_PORT || '993'),
    tls: true,
    authTimeout: 10000,
  }
};

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: parseInt(process.env.SMTP_PORT || '587'),
  secure: process.env.SMTP_PORT === '465',
  auth: { user: process.env.EMAIL_USER, pass: process.env.EMAIL_PASS },
});

const messageQueue = [];
const seenIds = new Set();

async function pollInbox() {
  try {
    const conn = await imaps.connect(IMAP_CONFIG);
    await conn.openBox('INBOX');
    const msgs = await conn.search(['UNSEEN'], { bodies: [''], markSeen: true });
    for (const msg of msgs) {
      const all = msg.parts.find(p => p.which === '');
      if (!all) continue;
      const parsed = await simpleParser(all.body);
      const id = parsed.messageId || `${Date.now()}-${Math.random()}`;
      if (!seenIds.has(id)) {
        seenIds.add(id);
        messageQueue.push({
          id,
          from: parsed.from?.value?.[0]?.address || '',
          subject: parsed.subject || '',
          text: parsed.text || ''
        });
      }
    }
    conn.end();
  } catch (e) {
    console.error('IMAP poll error:', e.message);
  }
}

setInterval(pollInbox, 30000);
pollInbox();

const api = express();
api.use(express.json());

api.get('/sessions/email/messages', (req, res) => {
  const limit = parseInt(req.query.limit) || 10;
  res.json(messageQueue.splice(0, limit));
});

api.post('/sessions/email/messages', async (req, res) => {
  const { to, subject, text } = req.body;
  try {
    await transporter.sendMail({ from: process.env.EMAIL_USER, to, subject, text });
    res.json({ ok: true });
  } catch (e) {
    console.error('SMTP send error:', e.message);
    res.status(500).json({ ok: false, error: e.message });
  }
});

api.get('/health', (req, res) => res.json({ ok: true }));

api.listen(3003, () => console.log('email-bridge listening on :3003'));
