#!/usr/bin/env bash
# Gateway integration test suite for VeriClaw HTTP server.
# Requires: curl, a running gateway on BASE_URL (default http://localhost:8787).
# Usage:  ./tests/gateway_integration_test.sh [base_url]
set -euo pipefail

BASE_URL="${1:-http://localhost:8787}"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  \033[31mFAIL\033[0m %s — %s\n" "$1" "$2"; }

# ---------------------------------------------------------------------------
# 1. GET /health → 200, body contains "ok"
# ---------------------------------------------------------------------------
echo "=== Health endpoint ==="
HTTP_CODE=$(curl -s -o /tmp/vc_health.json -w '%{http_code}' "$BASE_URL/health")
BODY=$(cat /tmp/vc_health.json)
if [ "$HTTP_CODE" = "200" ]; then pass "/health returns 200"; else fail "/health returns 200" "got $HTTP_CODE"; fi
if echo "$BODY" | grep -q '"ok"'; then pass "/health body contains ok"; else fail "/health body contains ok" "body: $BODY"; fi

# ---------------------------------------------------------------------------
# 2. POST /api/chat — valid JSON with message field
#    The gateway may return 200 (if a provider is configured) or 500
#    (structured JSON error when no provider is available). Either is
#    acceptable — the key assertion is that we get valid JSON back, not a crash.
# ---------------------------------------------------------------------------
echo "=== POST /api/chat (valid) ==="
HTTP_CODE=$(curl -s -o /tmp/vc_chat.json -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"message":"hello"}' "$BASE_URL/api/chat")
BODY=$(cat /tmp/vc_chat.json)
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "500" ]; then
  pass "/api/chat valid request returns 200 or 500"
else
  fail "/api/chat valid request returns 200 or 500" "got $HTTP_CODE"
fi
# Verify response is structured JSON (contains { })
if echo "$BODY" | grep -q '{'; then pass "/api/chat returns JSON body"; else fail "/api/chat returns JSON body" "body: $BODY"; fi

# ---------------------------------------------------------------------------
# 3. POST /api/chat — missing 'message' field → 400
# ---------------------------------------------------------------------------
echo "=== POST /api/chat (missing fields) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d '{"prompt":"hello"}' "$BASE_URL/api/chat")
if [ "$HTTP_CODE" = "400" ]; then pass "/api/chat missing message → 400"; else fail "/api/chat missing message → 400" "got $HTTP_CODE"; fi

# ---------------------------------------------------------------------------
# 4. POST /api/chat — invalid JSON → 400
# ---------------------------------------------------------------------------
echo "=== POST /api/chat (invalid JSON) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
  -X POST -H 'Content-Type: application/json' \
  -d 'not json at all' "$BASE_URL/api/chat")
if [ "$HTTP_CODE" = "400" ]; then pass "/api/chat invalid JSON → 400"; else fail "/api/chat invalid JSON → 400" "got $HTTP_CODE"; fi

# ---------------------------------------------------------------------------
# 5. GET /api/chat/stream → wrong method (expect 404 — only POST is routed)
# ---------------------------------------------------------------------------
echo "=== GET /api/chat/stream (wrong method) ==="
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/chat/stream")
if [ "$HTTP_CODE" = "404" ] || [ "$HTTP_CODE" = "405" ]; then
  pass "GET /api/chat/stream → $HTTP_CODE"
else
  fail "GET /api/chat/stream → 404 or 405" "got $HTTP_CODE"
fi

# ---------------------------------------------------------------------------
# 6. Security headers present on a typical response
# ---------------------------------------------------------------------------
echo "=== Security headers ==="
HEADERS=$(curl -s -D - -o /dev/null "$BASE_URL/health")

check_header() {
  local name="$1"
  if echo "$HEADERS" | grep -qi "$name"; then
    pass "Header $name present"
  else
    fail "Header $name present" "not found in response headers"
  fi
}

check_header "X-Content-Type-Options"
check_header "X-Frame-Options"
check_header "Cache-Control"

# ---------------------------------------------------------------------------
# 7. Rate limiting — send 130 requests quickly, verify at least one 429
# ---------------------------------------------------------------------------
echo "=== Rate limiting ==="
GOT_429=false
# Use a non-health endpoint so the rate limiter engages.
# /api/status returns 403 for non-localhost in production but is rate-limited.
# Use a lightweight endpoint that won't slow us down.
for i in $(seq 1 130); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/status")
  if [ "$CODE" = "429" ]; then
    GOT_429=true
    break
  fi
done
if $GOT_429; then pass "Rate limiter returns 429 after burst"; else fail "Rate limiter returns 429 after burst" "no 429 received in 130 requests"; fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
