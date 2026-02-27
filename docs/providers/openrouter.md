# OpenRouter Provider

OpenRouter provides a unified OpenAI-compatible API with access to 200+ models from OpenAI, Anthropic, Google, Meta, Mistral, and many others. VeriClaw connects via the `openai_compatible` provider type.

## Configuration

```json
{
  "providers": [{
    "kind": "openai_compatible",
    "base_url": "https://openrouter.ai/api/v1",
    "token": "sk-or-your_openrouter_api_key",
    "model": "anthropic/claude-3.5-sonnet"
  }]
}
```

## Popular Models

| Model slug | Provider | Notes |
|-----------|----------|-------|
| `anthropic/claude-3.5-sonnet` | Anthropic | Strong reasoning, long context |
| `openai/gpt-4o` | OpenAI | GPT-4o via OpenRouter |
| `google/gemini-pro-1.5` | Google | 1M token context |
| `meta-llama/llama-3.3-70b-instruct` | Meta | Open-weight, capable |
| `mistralai/mistral-large` | Mistral | European, GDPR-friendly |
| `nousresearch/hermes-3-llama-3.1-405b` | Nous | Large open-weight |

Browse the full list at [openrouter.ai/models](https://openrouter.ai/models).

## Getting an API Key

1. Sign up at [openrouter.ai](https://openrouter.ai)
2. Go to **Keys** and create a new API key
3. Add credits to your account (pay-as-you-go)
4. Set the key as `token` in your config or via `${OPENROUTER_API_KEY}`

## Why OpenRouter?

- **Model diversity** — switch models by changing one config line, no new API keys
- **Fallback routing** — OpenRouter can auto-route to the cheapest/fastest available provider
- **Cost visibility** — unified billing across all providers
- **Free tier** — some models are free with rate limits, useful for testing
