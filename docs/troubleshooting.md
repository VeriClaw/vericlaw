[← Back to README](../README.md)

# Troubleshooting

Common failure modes with exact error output and fix steps. All errors follow the pattern:

```
✗  [What happened]
   [Why it happened]
   → [What to do]
```

Run `vericlaw doctor` first — it identifies most issues automatically and tells you exactly what to run.

---

## 1. Signal bridge not responding

**When it happens:** `vericlaw doctor` or `vericlaw chat` shows a Signal failure.

**Error output:**

```
  Signal         ✗  Bridge not responding
                    The Signal bridge process may have stopped.
                    → Run: vericlaw onboard --repair-signal
                    → Or check: docs/troubleshooting.md
```

**Fix:**

```bash
vericlaw onboard --repair-signal
```

This restarts the `vericlaw-signal` companion binary and re-establishes the link with your Signal account. You do not need to re-scan the QR code if your device link is still active in Signal's Linked Devices list.

If the fix fails, open Signal on your phone, go to **Settings → Linked Devices**, remove the VeriClaw entry, and run `vericlaw onboard` to re-pair from scratch.

---

## 2. Provider API key invalid or expired

**When it happens:** After rotating an API key, or if the key was entered incorrectly during onboard.

**Error output:**

```
✗  Cannot connect to Anthropic API
   The API key in your config may be invalid or expired.
   → Run: vericlaw onboard (to re-enter your key)
   → Or check: https://console.anthropic.com/settings/keys
```

**Fix:**

```bash
vericlaw onboard
```

Re-run onboard and enter your new API key at step 1. The rest of your config (Signal pairing, workspace path) is preserved — onboard detects an existing config and only re-asks for the fields that need updating.

Alternatively, edit `~/.vericlaw/config.json` directly and update the `api_key` or `api_key_env` field, then verify with:

```bash
vericlaw doctor
```

---

## 3. Config file not found

**When it happens:** Running `vericlaw chat`, `vericlaw doctor`, or `vericlaw status` before completing onboard.

**Error output:**

```
✗  Config file not found
   Expected config at ~/.vericlaw/config.json
   → Run: vericlaw onboard (to create one)
```

**Fix:**

```bash
vericlaw onboard
```

This is the only way to create the config. VeriClaw does not generate a default config automatically — onboard validates your API key and Signal pairing inline, so the config is known-good from the moment it is written.

---

## 4. Memory database locked

**When it happens:** Two `vericlaw` processes are running simultaneously (e.g. a backgrounded `vericlaw chat` session plus a new one started in another terminal).

**Symptom:** SQLite lock errors in the terminal, or VeriClaw hangs on startup with no output.

**Error output (may appear in logs or stderr):**

```
memory.db: database is locked
```

**Fix:**

Find and kill the duplicate vericlaw process:

```bash
ps aux | grep vericlaw
kill <PID>
```

Then start VeriClaw again. Only one VeriClaw process should be running at a time. If you want VeriClaw to always be available in the background, install it as a systemd service (see [pi-deployment.md](pi-deployment.md)) — the service manager ensures only one instance runs.

---

## 5. Signal QR code not displaying correctly over SSH

**When it happens:** Running `vericlaw onboard` over an SSH session (e.g. in Termius on iOS, or any SSH client) and the QR code appears as garbled characters or a blank block.

**Cause:** The QR code is rendered as UTF-8 block characters (`▄`, `▀`, `█`). If your terminal's font does not include these characters, or if your locale is not set to UTF-8, the QR code will not render correctly.

**Fix:**

1. Ensure your terminal locale is set to UTF-8:

   ```bash
   export LANG=en_US.UTF-8
   export LC_ALL=en_US.UTF-8
   ```

   Add these to your `~/.bashrc` or `~/.zshrc` to make them permanent.

2. Use a font that includes Unicode block characters. In Termius on iOS, the default font works correctly. If you have changed the font, switch back to the default or choose another monospace font with Unicode coverage (e.g. JetBrains Mono, Fira Code, Noto Mono).

3. Make your terminal window wider. The QR code is approximately 30 characters wide — if your terminal is narrower than this, the QR code will wrap and become unscannable.

After making these changes, re-run:

```bash
vericlaw onboard
```

---

## 6. Voice messages not being transcribed

**When it happens:** You send a voice message to VeriClaw on Signal and receive a reply like:

```
I received your voice message but can't process audio yet. Please send a text message instead.
```

**Cause:** Voice transcription was either skipped during `vericlaw onboard`, or the transcription endpoint has not been configured.

**Fix — option A:** Re-run onboard and configure voice transcription when prompted. After Signal pairing, onboard asks whether you want to set up voice transcription and which endpoint to use. Groq is recommended (free, fast, accepts OGG natively from Signal).

**Fix — option B:** Edit `~/.vericlaw/config.json` directly and add a `voice` section:

```json
{
  "voice": {
    "transcription_endpoint": "https://api.groq.com/openai/v1/audio/transcriptions",
    "api_key_env": "GROQ_API_KEY",
    "model": "whisper-large-v3-turbo"
  }
}
```

Set your Groq API key:

```bash
export GROQ_API_KEY=gsk_...
```

Then verify with:

```bash
vericlaw doctor
```

The doctor output will show whether voice transcription is configured and reachable.

---

## Getting further help

- Run `vericlaw doctor` — covers the most common issues automatically
- Check the [GitHub issue tracker](https://github.com/vericlaw/vericlaw/issues) for known bugs
- File a new issue if your problem is not listed here
