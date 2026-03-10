# future/channels/

Ada channel adapter implementations that are not part of the v1.0-minimal release.

v1.0-minimal ships with two channels: CLI (for local development) and Signal (the primary user-facing channel). Everything else is preserved here.

## Contents

| Directory | Channel | Ada files | Returns at |
|-----------|---------|-----------|------------|
| `telegram/` | Telegram | `channels-telegram.ads/adb` | v1.1 (second native channel) |
| `discord/` | Discord | `channels-discord.ads/adb` | v1.1 |
| `slack/` | Slack | `channels-slack.ads/adb` | v1.1 |
| `whatsapp/` | WhatsApp | `channels-whatsapp.ads/adb` | v1.1 |
| `email/` | Email (IMAP/SMTP) | `channels-email.ads/adb` | v1.1 |
| `irc/` | IRC | `channels-irc.ads/adb` | v1.2 |
| `matrix/` | Matrix | `channels-matrix.ads/adb` | v1.2 |
| `mattermost/` | Mattermost | `channels-mattermost.ads/adb` | v1.2 |
| `adapters/` | SPARK adapter specs | `channels-adapters-discord.*`, `channels-adapters-email.*`, `channels-adapters-slack.*`, `channels-adapters-telegram.*`, `channels-adapters-whatsapp_bridge.*` | (with each channel) |

## To re-integrate a channel

1. Move the `.ads`/`.adb` files back to `src/channels/`
2. Move the corresponding bridge from `future/bridges/` to the repo root
3. Add the source files to `vericlaw.gpr`
4. Register the channel in `src/channels/channels.ads`
5. Update `config/config.example.json` with the channel's config block
6. Add documentation in `docs/`
