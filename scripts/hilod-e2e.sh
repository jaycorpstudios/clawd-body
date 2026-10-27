#!/bin/sh
# Runs a debug hilod with --stdout and answers its requests through `hilo buddy`. Usage: hilod-e2e.sh [workdir]
set -u
REPO=$(cd "$(dirname "$0")/.." && pwd)
W=${1:-$(mktemp -d)}
BIN=$REPO/daemon/.build/debug
(cd "$REPO/daemon" && swift build -q) || exit 1
cd "$W" || exit 1
rm -f h.sock out.jsonl err.log
# A relative socket path keeps it under sockaddr_un's 104 bytes wherever the workdir is.
export HILO_CONFIG="$W/config.json" HILO_DB="$W/hilo.sqlite" HILO_SOCKET=h.sock
"$BIN/hilod" --stdout --always-away --host work --socket h.sock > out.jsonl 2> err.log &
DAEMON=$!
trap 'kill $DAEMON 2>/dev/null' EXIT
until [ -S h.sock ]; do sleep 0.2; done
FAILED=0

newest_request() {
  n=0
  until id=$(grep "\"type\":\"$1\"" out.jsonl | tail -1 | sed -E 's/.*"request_id":"([^"]+)".*/\1/') && [ -n "$id" ] && [ "$id" != "${2:-}" ]; do
    sleep 0.2; n=$((n + 1)); [ $n -gt 50 ] && return 1
  done
  echo "$id"
}

buddy() { "$BIN/hilo" buddy "{\"v\":1,\"id\":\"$1\",\"ts\":0,\"type\":\"$2\",\"data\":$3}" > /dev/null; }

check() {
  if grep -q "$2" "$3"; then echo "ok   $1"; else echo "FAIL $1: $(cat "$3")"; FAILED=1; fi
}

printf '%s' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"e2e\",\"cwd\":\"$REPO\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"}}" \
  | "$BIN/hilo" hook > deny.out &
HOOK=$!
low=$(newest_request agent.needs_permission) || { echo "FAIL no permission request"; exit 1; }
buddy 01K8F400000000000000000101 permission.decision "{\"request_id\":\"$low\",\"decision\":\"deny\"}"
wait $HOOK
check "low-risk deny from the buddy reaches the hook" '"behavior":"deny"' deny.out

printf '%s' "{\"hook_event_name\":\"PreToolUse\",\"session_id\":\"e2e\",\"cwd\":\"$REPO\",\"tool_name\":\"AskUserQuestion\",\"tool_input\":{\"questions\":[{\"question\":\"Which store?\",\"header\":\"Store\",\"multiSelect\":false,\"options\":[{\"label\":\"SQLite\",\"description\":\"\"},{\"label\":\"Markdown\",\"description\":\"\"}]}]}}" \
  | "$BIN/hilo" hook > answer.out &
HOOK=$!
question=$(newest_request agent.question) || { echo "FAIL no question"; exit 1; }
buddy 01K8F400000000000000000102 question.answer "{\"request_id\":\"$question\",\"choice_index\":1,\"choice\":\"Markdown\"}"
wait $HOOK
check "question answered on the buddy reaches the hook" '"answers":{"Which store?":"Markdown"}' answer.out

printf '%s' "{\"hook_event_name\":\"PermissionRequest\",\"session_id\":\"e2e\",\"cwd\":\"$REPO\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"curl -H \\\"Authorization: Bearer abc123\\\" https://api.example.com\"}}" \
  | "$BIN/hilo" hook > high.out &
HOOK=$!
high=$(newest_request agent.needs_permission "$low") || { echo "FAIL no high-risk request"; exit 1; }
buddy 01K8F400000000000000000103 permission.decision "{\"request_id\":\"$high\",\"decision\":\"approve\"}"
buddy 01K8F400000000000000000104 permission.decision "{\"request_id\":\"$high\",\"decision\":\"deny\"}"
wait $HOOK
check "high-risk approve is ignored, deny is honored" '"behavior":"deny"' high.out
grep -q "abc123" out.jsonl && { echo "FAIL token reached the buddy"; FAILED=1; } || echo "ok   Authorization value redacted"

kill $DAEMON; wait $DAEMON 2>/dev/null
if node "$REPO/shared/src/cli.ts" validate < out.jsonl > validate.log 2>&1; then
  echo "ok   $(wc -l < out.jsonl | tr -d ' ') messages valid against the schema"
else
  echo "FAIL schema: $(cat validate.log)"; FAILED=1
fi
exit $FAILED
