# Ollama Provider

Ollama exposes a local OpenAI-compatible API, so VeriClaw connects to it via the `openai_compatible` provider type. No data leaves your machine.

## Prerequisites

Install and start Ollama:

```bash
# macOS / Linux
curl -fsSL https://ollama.com/install.sh | sh
ollama serve          # starts on http://localhost:11434 by default
ollama pull llama3    # download a model
```

## Configuration

```json
{
  "providers": [{
    "kind": "openai_compatible",
    "base_url": "http://localhost:11434/v1",
    "token": "ollama",
    "model": "llama3"
  }]
}
```

The `token` field is required by VeriClaw's schema but ignored by Ollama — any non-empty string works.

## Available Models

Any model pulled via `ollama pull <name>` is available. Popular choices:

| Model | Command | Notes |
|-------|---------|-------|
| Llama 3 8B | `ollama pull llama3` | Good general-purpose default |
| Mistral 7B | `ollama pull mistral` | Fast, strong reasoning |
| Phi-3 Mini | `ollama pull phi3` | Tiny, runs on CPU |
| Code Llama | `ollama pull codellama` | Code-focused |

Run `ollama list` to see what's already downloaded.

## Why Ollama?

- **Privacy** — all inference is local; no API keys, no data sent to third parties
- **Cost** — free after hardware costs
- **Offline** — works without internet access
- **Fits VeriClaw's air-gap deployment model** — pair with `channels: [{kind: cli}]` for a fully self-contained setup
