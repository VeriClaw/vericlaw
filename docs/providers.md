# LLM Providers

[← Back to README](../README.md)

VeriClaw supports **5 provider families** — OpenAI, Anthropic, Google Gemini, Azure AI Foundry, and any OpenAI-compatible endpoint (Ollama, Groq, OpenRouter, LiteLLM, LM Studio). Configure one or many; VeriClaw routes requests across them automatically with ordered failover.

## Provider Reference

| Kind | `kind` in config | Models | Notes |
|------|------------------|--------|-------|
| OpenAI | `openai` | gpt-4o, gpt-4-turbo | First-party; streaming supported |
| Anthropic | `anthropic` | claude-3-5-sonnet-20241022, claude-3-7-sonnet | First-party; streaming supported |
| Google Gemini | `gemini` | gemini-2.0-flash (default), gemini-1.5-pro | Native integration |
| Azure AI Foundry | `azure_foundry` | Any deployed model | Requires `base_url`, `deployment`, `api_version` |
| OpenAI-compatible | `openai_compatible` | Anything behind an OpenAI-shaped API | `base_url` covers Ollama, Groq, OpenRouter, LiteLLM, LM Studio |

## Multi-Provider Routing

Multi-provider routing is a key VeriClaw differentiator. Instead of hard-coding a single LLM, you list providers in priority order inside the `providers` array:

1. **`providers[0]` — Primary.** All requests go here first.
2. **`providers[1]` — Dedicated failover.** Used when the primary returns an error or times out.
3. **`providers[2..n]` — Long-tail fallbacks.** Tried in order if both primary and failover fail.

This gives you automatic resilience across providers with zero application-level retry logic:

```json
{
  "providers": [
    { "kind": "openai", "api_key": "sk-...", "model": "gpt-4o" },
    { "kind": "anthropic", "api_key": "sk-ant-...", "model": "claude-3-5-sonnet-20241022" },
    { "kind": "openai_compatible", "base_url": "https://api.groq.com/openai/v1",
      "token": "gsk_...", "model": "llama-3.3-70b-versatile" }
  ]
}
```

## Streaming

- **CLI mode** — always-on. Tokens are printed as they arrive for OpenAI and Anthropic providers.
- **Gateway mode** — SSE (Server-Sent Events) token output.
- **Fallback** — providers that don't support streaming fall back gracefully to non-streaming responses. No flag needed.

## Configuration Examples

### OpenAI

```json
{
  "providers": [
    { "kind": "openai", "api_key": "sk-...", "model": "gpt-4o" }
  ]
}
```

### Anthropic

```json
{
  "providers": [
    { "kind": "anthropic", "api_key": "sk-ant-...", "model": "claude-3-5-sonnet-20241022" }
  ]
}
```

### Google Gemini

```json
{
  "providers": [
    { "kind": "gemini", "api_key": "AIza...", "model": "gemini-2.0-flash" }
  ]
}
```

### Azure AI Foundry

```json
{
  "providers": [
    { "kind": "azure_foundry", "api_key": "AZURE_KEY",
      "base_url": "https://YOUR-HUB.openai.azure.com",
      "deployment": "gpt-4o", "api_version": "2024-02-15-preview" }
  ]
}
```

### OpenAI-Compatible

All OpenAI-compatible providers use `kind: "openai_compatible"` with a `base_url` pointing at the target API.

#### Groq (fastest inference)

```json
{
  "providers": [
    { "kind": "openai_compatible", "base_url": "https://api.groq.com/openai/v1",
      "token": "gsk_...", "model": "llama-3.3-70b-versatile" }
  ]
}
```

#### Ollama (local, no API key)

```json
{
  "providers": [
    { "kind": "openai_compatible", "base_url": "http://localhost:11434/v1",
      "token": "ollama", "model": "llama3" }
  ]
}
```

The `token` field is required by VeriClaw's schema but ignored by Ollama — any non-empty string works.

#### OpenRouter (200+ models, one key)

```json
{
  "providers": [
    { "kind": "openai_compatible", "base_url": "https://openrouter.ai/api/v1",
      "token": "sk-or-...", "model": "anthropic/claude-3.5-sonnet" }
  ]
}
```

#### LiteLLM

```json
{
  "providers": [
    { "kind": "openai_compatible", "base_url": "http://localhost:4000/v1",
      "token": "sk-litellm-...", "model": "gpt-4o" }
  ]
}
```

## Detailed Guides

- [Ollama (local, free)](providers/ollama.md) — air-gapped setup, available models, privacy benefits
- [Groq (fastest inference)](providers/groq.md) — LPU hardware, ~750 tok/s, model list
- [OpenRouter (200+ models)](providers/openrouter.md) — unified billing, model diversity, free tier
