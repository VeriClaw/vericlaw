#!/usr/bin/env bash
# VeriClaw idle RSS benchmark
# Usage: ./scripts/bench-rss.sh [binary_path]
set -e
BINARY="${1:-./vericlaw}"

echo "=== VeriClaw Idle RSS Benchmark ==="
echo "Binary: $BINARY"
echo "Size:   $(du -h "$BINARY" | cut -f1)"
echo ""

# Start vericlaw in --version mode just to measure startup
START_NS=$(date +%s%N)
"$BINARY" version 2>/dev/null
END_NS=$(date +%s%N)
STARTUP_MS=$(( (END_NS - START_NS) / 1000000 ))
echo "Startup latency: ${STARTUP_MS}ms"
echo ""

# Measure idle RSS by running gateway in background with a no-op config
# Create temp config with no channels enabled
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/config.json" << 'EOF'
{
  "providers": [{"kind": "openai_compatible", "base_url": "http://localhost:1", "token": "test", "model": "test"}],
  "channels": [],
  "memory": {"max_history": 10}
}
EOF

# Start gateway in background
"$BINARY" --config "$TMPDIR/config.json" agent "ping" 2>/dev/null &
PID=$!
sleep 2

# Measure RSS
if [[ "$(uname)" == "Darwin" ]]; then
  RSS_KB=$(ps -o rss= -p $PID 2>/dev/null | tr -d ' ')
else
  RSS_KB=$(cat /proc/$PID/status 2>/dev/null | grep VmRSS | awk '{print $2}')
fi

kill $PID 2>/dev/null
rm -rf "$TMPDIR"

if [[ -n "$RSS_KB" ]]; then
  RSS_MB=$(echo "scale=2; $RSS_KB / 1024" | bc)
  echo "Idle RSS: ${RSS_MB} MB (${RSS_KB} KB)"
  echo ""
  echo "=== Comparison ==="
  echo "VeriClaw: ${RSS_MB} MB"
  echo "ZeroClaw: <5 MB (Rust/Tokio)"
  echo "NullClaw: ~1 MB (Zig, static)"
  echo "Target:   <5 MB (match ZeroClaw)"
else
  echo "Could not measure RSS (binary may not support gateway without channels)"
fi
