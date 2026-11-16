#!/usr/bin/env bash
# Tests of the egress proxy image: allowlisted domains pass, anything else is denied, and each request is logged.
# Needs internet access (it fetches from api.github.com through the proxy). Usage: test-proxy.sh <container tool> <image>
set -euo pipefail
CONTAINER=$1
IMAGE=$2
NAME=egress-proxy-test-$$
failures=0
trap '"$CONTAINER" rm -f "$NAME" >/dev/null' EXIT

check() {  # check <description> <command...>
  if "${@:2}"; then echo "  ok: $1"; else echo "  FAILED: $1"; failures=$((failures + 1)); fi
}

# status_through_proxy <url>: the server's HTTP status or, when the proxy refused to open an HTTPS tunnel (no response
# from the server: 000), the proxy's answer to CONNECT.
status_through_proxy() {
  local connect code
  read -r connect code < <(curl -s -o /dev/null -w '%{http_connect} %{http_code}' --max-time 20 -x "$PROXY" "$1" || true)
  if [[ "$code" == 000 ]]; then echo "$connect"; else echo "$code"; fi
}

"$CONTAINER" run -d --name "$NAME" -p 127.0.0.1::3128 "$IMAGE" >/dev/null
PROXY="http://$("$CONTAINER" port "$NAME" 3128 | head -1)"
for _ in {1..50}; do curl -s -o /dev/null -x "$PROXY" http://denied.invalid/ && break; sleep 0.2; done

echo "Egress proxy at $PROXY"
check "an allowlisted domain over HTTPS passes" test "$(status_through_proxy https://api.github.com/zen)" = 200
check "a domain absent from the allowlist is denied (HTTPS)" test "$(status_through_proxy https://example.com/)" = 403
check "a domain absent from the allowlist is denied (HTTP)" test "$(status_through_proxy http://example.com/)" = 403
check "an IP address is denied, even one of an allowlisted domain" test "$(status_through_proxy https://140.82.112.5/)" = 403
check "an allowlisted domain on another port is denied" test "$(status_through_proxy https://api.github.com:8443/)" = 403
check "a look-alike domain is denied" test "$(status_through_proxy https://github.com.example.com/)" = 403

# logged <text>: the proxy's output shows the line within 15 s (Squid's log daemon writes in batches).
logged() {
  for _ in {1..30}; do
    "$CONTAINER" logs "$NAME" 2>&1 | grep -q "$1" && return 0
    sleep 0.5
  done
  return 1
}
check "the allowed request is logged" logged "TCP_TUNNEL/200 CONNECT api.github.com:443"
check "the denied request is logged" logged "TCP_DENIED/403 CONNECT example.com:443"

if ((failures > 0)); then echo "$failures check(s) failed"; exit 1; fi
echo "All checks passed"
