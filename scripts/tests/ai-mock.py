#!/usr/bin/env python3
"""Fake Ollama + Anthropic Messages API for scripts/tests/test-huilo-ai.sh.

  ai-mock.py PORT LOGFILE     every POST body is appended to LOGFILE (JSON lines)
A question containing REFUSE gets stop_reason "refusal"; the Claude key must be sk-ant-test.
"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
LOG = sys.argv[2]
REPLY = {"answer": "Чтобы установить **Telegram**, выполните команду ниже.", "commands": [
    {"command": "echo installing telegram-desktop", "explain": "Установит Telegram", "risk": "caution"},
    {"command": "rm -rf ~", "explain": "пример опасной", "risk": "safe"}], "follow_up": "Запустить его потом?"}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, obj, code=200):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path == "/api/version": self._send({"version": "0.40.14"})
        elif self.path == "/api/tags": self._send({"models": [{"name": "qwen3:4b", "model": "qwen3:4b"}]})
        else: self._send({"error": "nf"}, 404)
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        with open(LOG, "a") as f: f.write(json.dumps({"path": self.path, "headers": dict(self.headers), "body": body}, ensure_ascii=False) + "\n")
        last = body["messages"][-1]["content"]
        if self.path == "/api/chat":
            self._send({"message": {"role": "assistant", "content": json.dumps(REPLY, ensure_ascii=False)}, "done": True})
        elif self.path == "/v1/messages":
            if "REFUSE" in str(last): self._send({"type": "message", "role": "assistant", "content": [], "stop_reason": "refusal", "stop_details": {"type": "refusal", "category": None}}); return
            if self.headers.get("x-api-key") != "sk-ant-test": self._send({"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}, 401); return
            self._send({"type": "message", "role": "assistant", "model": body["model"], "content": [{"type": "thinking", "thinking": "", "signature": "sig"}, {"type": "text", "text": json.dumps(REPLY, ensure_ascii=False)}], "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}})
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
