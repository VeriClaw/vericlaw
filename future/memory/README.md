# future/memory/

Memory subsystem extensions not included in v1.0-minimal.

v1.0-minimal uses SQLite with conversation history, basic facts store, and FTS5 search. Vector memory and context compaction are more complex and return in v1.1.

## Contents

| Directory | What it is | Returns at |
|-----------|-----------|------------|
| `vector/` | Vector similarity search (`memory-vector.*`) using sqlite-vec extension | v1.1 |
| `compaction/` | Context compaction — automatic summarisation of long conversation histories to stay within context windows | v1.1 |

## v1.0-minimal memory (stays in src/)

- `memory-sqlite.*` — SQLite WAL-mode database for conversation history, facts, FTS5 full-text search, cron schedule storage
- Maximum history configurable via `memory.max_history` (default: 50 messages)
- Facts stored as key-value pairs, recalled by the agent across sessions
