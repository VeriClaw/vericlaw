# Groq Provider

Groq is fully supported via the `openai_compatible` provider type.

## Configuration

```json
{
  "providers": [{
    "kind": "openai_compatible",
    "base_url": "https://api.groq.com/openai/v1",
    "token": "gsk_your_groq_api_key",
    "model": "llama-3.3-70b-versatile"
  }]
}
```

See [`config/examples/groq.json`](../../config/examples/groq.json) for a full working example.

## Available Models

| Model | Notes |
|-------|-------|
| `llama-3.3-70b-versatile` | Recommended — fast and capable |
| `llama-3.1-8b-instant` | Ultra-fast, lowest latency |
| `mixtral-8x7b-32768` | Long context window (32k tokens) |
| `gemma2-9b-it` | Google Gemma via Groq |

## Getting an API Key

1. Sign up at [console.groq.com](https://console.groq.com)
2. Navigate to **API Keys** and create a new key
3. Set it as the `token` value in your VeriClaw config (or use the `${GROQ_API_KEY}` env-var substitution)

## Why Groq?

Groq's LPU hardware delivers the fastest inference speeds available (~750 tokens/second on Llama 3.3 70B). This makes it ideal for real-time chat applications where latency matters more than cost-per-token.
