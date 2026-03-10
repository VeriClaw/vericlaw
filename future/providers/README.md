# future/providers/

Ada LLM provider implementations not included in v1.0-minimal.

v1.0-minimal ships with two providers:
- **Anthropic** (`providers-anthropic.*`) — native first-class implementation for Claude
- **OpenAI-compatible** (`providers-openai_compatible.*`) — generic adapter covering Azure AI Foundry, Gemini, Ollama, OpenRouter, Groq, DeepSeek, and any OpenAI-format endpoint

Named provider adapters and the failover routing system are preserved here.

## Contents

| Directory | What it is | Returns at |
|-----------|-----------|------------|
| `openai/` | Dedicated OpenAI adapter (`providers-openai.*`) with native features beyond the compat layer | v1.1 |
| `gemini/` | Dedicated Google Gemini adapter (`providers-gemini.*`) with native features | v1.1 |
| `failover/` | Provider failover chain and runtime routing (`gateway-provider-routing.*`, `gateway-provider-runtime_routing.*`) | v1.2 |

## Design note

The OpenAI-compatible provider in `src/providers/` already covers Azure AI Foundry, Gemini (via its OpenAI-compatible mode), Ollama, Groq, OpenRouter, DeepSeek, and Mistral. Dedicated adapters return when users need provider-specific features beyond the common API (e.g., OpenAI Assistants, Gemini grounding, Azure-specific auth flows).
