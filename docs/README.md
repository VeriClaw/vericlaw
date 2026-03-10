# VeriClaw Documentation

[← Back to README](../README.md)

## 🚀 Getting Started

| Guide | Description |
|-------|-------------|
| [Getting Started](getting-started.md) | Install → onboard → doctor → chat walkthrough |
| [Installation](installation.md) | All installation methods (native, Docker, Homebrew, Scoop) |
| [Project README](../README.md) | Project overview and quick-start basics |

## 🔧 Configuration

| Guide | Description |
|-------|-------------|
| [Providers](providers.md) | LLM provider configuration and selection |
| [Channels](channels.md) | Messaging channel setup and options |
| [Tools](tools.md) | Tool reference — 3 built-in tools (file_io, shell, cron) |

## 📖 Reference

| Guide | Description |
|-------|-------------|
| [Testing](testing.md) | Tests, build profiles, CI pipeline, and gate commands |
| [Benchmarks](benchmarks.md) | Performance comparison and methodology |

> **Gateway API** and **Operations** docs (Prometheus metrics, SIGHUP reload, docker-compose deployment) are in [`future/docs/`](../future/docs/) — these features return in v1.2–v1.3.

## 🏗️ Architecture & Design

| Guide | Description |
|-------|-------------|
| [Architecture](../ARCHITECTURE.md) | System design and 3-layer model |
| [Security](../SECURITY.md) | Threat model, controls, and pre-deployment checklist |
| [Project Overview](project-overview.md) | Strategic overview and capability inventory |
| [Ada Coding Practices](ada-coding-practices.md) | Ada/SPARK coding conventions |

## 🤝 Contributing

| Guide | Description |
|-------|-------------|
| [Contributing](../CONTRIBUTING.md) | Developer guide, PR process, and SPARK requirements |
| [Changelog](../CHANGELOG.md) | Release notes |

## 📂 Channel Setup Guides

Signal setup is covered in [Channels](channels.md). Additional channel setup guides (WhatsApp, Slack, Discord, Email, IRC, Matrix, Mattermost — returning in v1.1) are in [`future/docs/setup/`](../future/docs/setup/).

## 📂 Provider Guides

Detailed provider setup in [`providers/`](providers/):

- [Ollama](providers/ollama.md)
- [Groq](providers/groq.md)
- [OpenRouter](providers/openrouter.md)

## 📂 Runbooks

- [Operator Runbook](runbooks/operator-runbook.md) — Operational procedures and incident response
