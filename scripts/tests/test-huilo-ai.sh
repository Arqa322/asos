#!/usr/bin/env bash
# Tests huilo-ai (ии) against a fake model server: both brains, the request
# shape sent to Claude, errors, refusals, danger detection, and that nothing
# runs without confirmation. No network, no real model.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AI="$ROOT/archiso/airootfs/usr/local/bin/huilo-ai"
T=$(mktemp -d)
trap 'kill "$MOCK" 2>/dev/null; rm -rf "$T"' EXIT
PORT=$((20000 + RANDOM % 20000))
python3 "$ROOT/scripts/tests/ai-mock.py" "$PORT" "$T/log.jsonl" & MOCK=$!
for _ in $(seq 1 50); do curl -fs "127.0.0.1:$PORT/api/version" >/dev/null && break; sleep 0.1; done
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" LANG=C.UTF-8
mkdir -p "$HOME" "$T/bin"; printf '#!/bin/sh\nexit 0\n' >"$T/bin/ollama"; chmod +x "$T/bin/ollama"
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
CL=(env HUILO_AI_API_URL="http://127.0.0.1:$PORT/v1/messages" HUILO_AI_BACKEND=claude)
LO=(env PATH="$T/bin:$PATH" OLLAMA_HOST="127.0.0.1:$PORT" HUILO_AI_BACKEND=local)

out=$("${LO[@]}" "$AI" как установить телеграм </dev/null 2>&1)
check "local: answer shown" '[[ "$out" == *"Telegram"* ]]'
check "local: danger flagged by the local check" '[[ "$out" == *"ОПАСНО"* ]]'
check "local: structured output + system prompt" 'tail -1 "$T/log.jsonl" | jq -e ".path == \"/api/chat\" and .body.format.type == \"object\" and .body.messages[0].role == \"system\"" >/dev/null'

out=$("${CL[@]}" ANTHROPIC_API_KEY=wrong "$AI" привет </dev/null 2>&1); rc=$?
check "claude: bad key explained" '[[ "$out" == *"ключ не подошёл"* && $rc -ne 0 ]]'
out=$("${CL[@]}" ANTHROPIC_API_KEY=sk-ant-test "$AI" REFUSE </dev/null 2>&1); rc=$?
check "claude: refusal handled" '[[ "$out" == *"отказался"* && $rc -ne 0 ]]'
out=$(echo "error: target not found: telegram" | "${CL[@]}" ANTHROPIC_API_KEY=sk-ant-test "$AI" 2>&1); rc=$?
check "claude: piped output explained" '[[ "$out" == *"Telegram"* && $rc -eq 0 ]]'
req=$(tail -1 "$T/log.jsonl")
check "claude: API version + fallback beta headers" 'jq -e ".headers[\"anthropic-version\"] == \"2026-10-21\" and .headers[\"anthropic-beta\"] == \"server-side-fallback-2026-07-01\"" <<<"$req" >/dev/null'
check "claude: model, fallbacks, effort, json_schema" 'jq -e ".body.model == \"claude-opus-5-5\" and .body.fallbacks == \"default\" and .body.output_config.effort == \"medium\" and .body.output_config.format.type == \"json_schema\" and (.body | has(\"thinking\") | not)" <<<"$req" >/dev/null'
check "claude: piped text and computer facts in the question" 'jq -e ".body.messages[0].content | contains(\"target not found\") and contains(\"[Computer:\")" <<<"$req" >/dev/null'
chat=$(ls -t "$XDG_STATE_HOME"/huilo/ai/chat-*.json | head -1)
check "claude: assistant turn kept whole (thinking block too)" 'jq -e ".[1].content | map(.type) == [\"thinking\",\"text\"]" "$chat" >/dev/null'

# interactive: refuse the dangerous command, then quit; the home must survive
printf '2\nнет\n6\n' >"$T/in"
script -q -e -c "$(printf '%q ' "${LO[@]}" "$AI" тест)" /dev/null <"$T/in" >"$T/tty.log" 2>&1
check "interactive: dangerous command needs the word, home untouched" 'grep -q "Отменено" "$T/tty.log" && [[ -d "$HOME/.config" ]]'
printf '1\nд\n' >"$T/in"
script -q -e -c "$(printf '%q ' "${LO[@]}" "$AI" тест)" /dev/null <"$T/in" >"$T/tty.log" 2>&1
check "interactive: confirmed command runs" 'grep -q "installing telegram-desktop" "$T/tty.log" && grep -q "готово" "$T/tty.log"'
exit $fail
