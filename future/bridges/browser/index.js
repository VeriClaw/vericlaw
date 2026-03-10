'use strict';

/**
 * VeriClaw Browser Bridge
 *
 * A lightweight Express REST server wrapping Puppeteer (Chromium).
 * Exposes browse and screenshot endpoints for the Ada agent.
 *
 * API:
 *   GET  /health                                      -> {ok:true}
 *   POST /browse      {url, timeout_ms}               -> {ok, text, title} | {ok:false, error}
 *   POST /screenshot  {url, timeout_ms}               -> {ok, png_base64, title} | {ok:false, error}
 *
 * Env vars:
 *   PORT  HTTP port (default 3007)
 */

const express = require('express');
const puppeteer = require('puppeteer');
const dns = require('dns').promises;
const { URL } = require('url');

const PORT = parseInt(process.env.PORT || '3007', 10);

// Simple semaphore — max 2 concurrent browser requests.
let concurrentRequests = 0;
const MAX_CONCURRENT = 2;

// Private IP range check.
function isPrivateIP(ip) {
  // Strip IPv6-mapped IPv4 prefix.
  const addr = ip.replace(/^::ffff:/, '');
  if (addr === '::1' || addr === 'localhost') return true;
  const parts = addr.split('.').map(Number);
  if (parts.length !== 4) return false;
  const [a, b] = parts;
  return (
    a === 127 ||
    a === 10 ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168)
  );
}

async function checkPrivateURL(rawURL) {
  let parsed;
  try {
    parsed = new URL(rawURL);
  } catch {
    return { blocked: true, reason: 'malformed URL' };
  }
  // Only allow http and https schemes.
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return { blocked: true, reason: 'disallowed scheme: ' + parsed.protocol };
  }
  const hostname = parsed.hostname;
  // Quick check for obvious literals.
  if (isPrivateIP(hostname)) return { blocked: true, reason: 'private IP' };
  try {
    const { address } = await dns.lookup(hostname);
    if (isPrivateIP(address)) return { blocked: true, reason: 'resolves to private IP' };
  } catch {
    // DNS failure — let Puppeteer handle it.
  }
  return { blocked: false };
}

let browser = null;

async function getBrowser() {
  if (!browser || !browser.isConnected()) {
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--disable-extensions',
        '--disable-background-networking',
      ],
    });
  }
  return browser;
}

async function withPage(timeoutMs, fn) {
  const b = await getBrowser();
  const page = await b.newPage();
  page.setDefaultNavigationTimeout(timeoutMs);
  try {
    return await fn(page);
  } finally {
    await page.close().catch(() => {});
  }
}

const app = express();
app.use(express.json());

app.get('/health', (_req, res) => res.json({ ok: true }));

app.post('/browse', async (req, res) => {
  const { url, timeout_ms = 15000 } = req.body || {};
  if (!url) return res.status(400).json({ ok: false, error: 'url required' });

  const { blocked, reason } = await checkPrivateURL(url);
  if (blocked) return res.status(403).json({ ok: false, error: reason || 'blocked URL' });

  if (concurrentRequests >= MAX_CONCURRENT) {
    return res.status(429).json({ ok: false, error: 'too many concurrent requests' });
  }
  concurrentRequests++;
  try {
    const result = await withPage(timeout_ms, async (page) => {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeout_ms });
      const title = await page.title();
      const text = await page.evaluate(() => document.body ? document.body.innerText : '');
      return { ok: true, text, title };
    });
    res.json(result);
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  } finally {
    concurrentRequests--;
  }
});

app.post('/screenshot', async (req, res) => {
  const { url, timeout_ms = 15000 } = req.body || {};
  if (!url) return res.status(400).json({ ok: false, error: 'url required' });

  const { blocked: blocked2, reason: reason2 } = await checkPrivateURL(url);
  if (blocked2) return res.status(403).json({ ok: false, error: reason2 || 'blocked URL' });

  if (concurrentRequests >= MAX_CONCURRENT) {
    return res.status(429).json({ ok: false, error: 'too many concurrent requests' });
  }
  concurrentRequests++;
  try {
    const result = await withPage(timeout_ms, async (page) => {
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeout_ms });
      const title = await page.title();
      const buf = await page.screenshot({ type: 'png', fullPage: false });
      return { ok: true, png_base64: buf.toString('base64'), title };
    });
    res.json(result);
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  } finally {
    concurrentRequests--;
  }
});

app.listen(PORT, '127.0.0.1', () => {
  console.log(`VeriClaw browser bridge listening on 127.0.0.1:${PORT}`);
});

// Graceful shutdown — close the browser on exit.
process.on('SIGTERM', async () => {
  if (browser) await browser.close().catch(() => {});
  process.exit(0);
});
