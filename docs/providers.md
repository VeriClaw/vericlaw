[← Back to README](../README.md)

# Providers

VeriClaw v0.3.0 supports two provider families: **Anthropic** (native, first-class) and **OpenAI-compatible** (any endpoint following the OpenAI chat completions API format). Configure one in `~/.vericlaw/config.json`, or let `vericlaw onboard` write it for you.

---

## Anthropic

Anthropic is the primary, most-tested path. It is the default recommended during `vericlaw onboard`.

### Recommended model

```
claude-sonnet-4-20250514
```

This is the model VeriClaw uses after a default `vericlaw onboard` run. It supports streaming, tool use, and vision (image inputs).

### Config

```json
{
  "agent_name": "VeriClaw",
  "provider": {
    "kind": "anthropic",
    "api_key_env": "ANTHROPIC_API_KEY",
    "model": "claude-sonnet-4-20250514"
  }
}
```

`api_key_env` names an environment variable that holds your key. Alternatively, use `api_key` with the key value directly — but prefer the env var to keep keys out of the config file.

### Getting an API key

1. Go to [console.anthropic.com](https://console.anthropic.com)
2. Create an account or sign in
3. Navigate to **API Keys** and create a new key
4. The key starts with `sk-ant-`

Set it as an environment variable:

```bash
export ANTHROPIC_API_KEY=sk-ant-api03-...
```

Or add it to your shell profile (`~/.zshrc`, `~/.bashrc`) so it persists.

---

## OpenAI-compatible

The `openai-compatible` kind works with any HTTP API that follows the OpenAI chat completions format. This covers hosted services, local models, and gateway proxies.

### Config fields

| Field | Required | Description |
|---|---|---|
| `kind` | Yes | Always `"openai-compatible"` |
| `base_url` | Yes | The API endpoint (must include path prefix, e.g. `/v1`) |
| `api_key_env` | Yes* | Environment variable holding the API key |
| `api_key` | Yes* | API key value directly (prefer `api_key_env`) |
| `model` | Yes | Model name as the endpoint expects it |
| `extra_headers` | No | Additional HTTP headers (e.g. API version for Azure) |

*One of `api_key_env` or `api_key` is required. For Ollama, use `"api_key": "ollama"` — any non-empty string works.

### Vision support

Both Anthropic and most OpenAI-compatible endpoints support image inputs. Send an image on Signal or attach one in a tool call and VeriClaw will pass it through to the provider. Check your provider's documentation to confirm vision support for the specific model you are using.

---

## OpenAI-compatible examples

### Azure AI Foundry

```json
{
  "provider": {
    "kind":        "openai-compatible",
    "base_url":    "https://YOUR-RESOURCE.openai.azure.com/openai/deployments/gpt-4o",
    "api_key_env": "AZURE_API_KEY",
    "model":       "gpt-4o",
    "extra_headers": {
      "api-version": "2024-12-01-preview"
    }
  }
}
```

Replace `YOUR-RESOURCE` with your Azure resource name and `gpt-4o` with your deployment name.

### Google Gemini

```json
{
  "provider": {
    "kind":        "openai-compatible",
    "base_url":    "https://generativelanguage.googleapis.com/v1beta/openai",
    "api_key_env": "GEMINI_API_KEY",
    "model":       "gemini-2.0-flash"
  }
}
```

Get a Gemini API key at [aistudio.google.com](https://aistudio.google.com).

### Ollama (local, no API key)

```json
{
  "provider": {
    "kind":    "openai-compatible",
    "base_url": "http://localhost:11434/v1",
    "api_key":  "ollama",
    "model":    "llama3.2:3b"
  }
}
```

Ollama must be running locally (`ollama serve`). The `api_key` value is ignored by Ollama but required by VeriClaw's config schema — any non-empty string works.

### OpenRouter

```json
{
  "provider": {
    "kind":        "openai-compatible",
    "base_url":    "https://openrouter.ai/api/v1",
    "api_key_env": "OPENROUTER_API_KEY",
    "model":       "anthropic/claude-sonnet-4"
  }
}
```

OpenRouter gives you access to 200+ models under a single API key. Get a key at [openrouter.ai](https://openrouter.ai).

### Groq

```json
{
  "provider": {
    "kind":        "openai-compatible",
    "base_url":    "https://api.groq.com/openai/v1",
    "api_key_env": "GROQ_API_KEY",
    "model":       "llama-3.3-70b-versatile"
  }
}
```

Groq runs on LPU hardware and delivers very fast inference (~750 tok/s). Recommended as the voice transcription endpoint when using Whisper-compatible transcription. Get a key at [console.groq.com](https://console.groq.com).

### DeepSeek

```json
{
  "provider": {
    "kind":        "openai-compatible",
    "base_url":    "https://api.deepseek.com/v1",
    "api_key_env": "DEEPSEEK_API_KEY",
    "model":       "deepseek-chat"
  }
}
```

Get a key at [platform.deepseek.com](https://platform.deepseek.com).

---

## Choosing a provider

| Situation | Recommendation |
|---|---|
| First-time setup, want the best results | Anthropic — `claude-sonnet-4-20250514` |
| Want the fastest responses | Groq — `llama-3.3-70b-versatile` |
| Want to run fully local, no API calls | Ollama — any model you have pulled |
| Want access to many models with one key | OpenRouter |
| Already have Azure credits | Azure AI Foundry |
