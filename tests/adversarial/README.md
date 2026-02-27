# Adversarial Test Corpus

Security test inputs for VeriClaw AI agent. Run as part of the integration test suite.

## Categories
- `prompt_injection/` — System prompt overrides, role confusion, instruction extraction
- `output_manipulation/` — Shell commands, SQL injection, code injection in model responses
- `resource_exhaustion/` — Deeply nested structures, infinite loops, excessive allocation
- `encoding_attacks/` — Unicode homoglyphs, zero-width chars, RTL override, null bytes
