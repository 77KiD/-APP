#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
python3 -m http.server 4173 --directory "$root/app/build/web" >/tmp/verify-41-web.log 2>&1 &
web_pid=$!
chrome_dir="$(mktemp -d)"
google-chrome --headless=new --disable-gpu --no-sandbox \
  --user-data-dir="$chrome_dir" --remote-debugging-port=9222 \
  http://127.0.0.1:4173 >/tmp/chrome-verify-41.log 2>&1 &
chrome_pid=$!
cleanup() {
  kill "$web_pid" "$chrome_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 2
node "$root/app/tool/wait_verify_41.mjs"
