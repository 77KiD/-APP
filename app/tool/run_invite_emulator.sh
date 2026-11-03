#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -m http.server 4173 --directory "$root/app/build/web" >/tmp/invite-web.log 2>&1 &
web_pid=$!
google-chrome --headless=new --disable-gpu --no-sandbox \
  --user-data-dir=/tmp/chrome-invite --remote-debugging-port=9222 \
  http://127.0.0.1:4173 >/tmp/chrome-invite.log 2>&1 &
chrome_pid=$!
cleanup() {
  kill "$web_pid" "$chrome_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

python3 - <<'PY'
import socket
import sys
import time

deadline = time.monotonic() + 60
while time.monotonic() < deadline:
    try:
        with socket.create_connection(("127.0.0.1", 9222), timeout=0.5):
            sys.exit(0)
    except OSError:
        time.sleep(0.5)
print(
    "timed out after 60s waiting for Chrome to listen on 127.0.0.1:9222",
    file=sys.stderr,
)
sys.exit(1)
PY

node "$root/app/tool/wait_invite_page.mjs"
