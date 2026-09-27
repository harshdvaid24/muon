#!/usr/bin/env python3
"""Local Needle 3 server for Muon (optional, experimental).

    python3 -m venv ~/.muon/needle && ~/.muon/needle/bin/pip install cactus-needle
    ~/.muon/needle/bin/python scripts/needle-serve.py        # 127.0.0.1:8766

POST /v1/route {"query": "...", "tools": [MCP tool schemas]} -> {"calls", "confidence", "reasoning", "ms", "engine"}
GET  /health
Tools are sent by Muon; the agent is rebuilt only when the tool list changes. Nothing leaves the Mac.
"""
import hashlib, io, json, os, sys, time, urllib.request, zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer

os.environ.setdefault("NEEDLE_TELEMETRY", "0")
PORT = int(os.environ.get("NEEDLE_PORT", "8766"))
CACHE = os.path.expanduser("~/.cache/cactus-needle")
ENGINE_FALLBACK = "https://huggingface.co/Cactus-Compute/needle3/resolve/main/python/cactus_needle-3.0.1-py3-none-macosx_11_0_arm64.whl"

def ensure_engine():
    """cactus-needle 3.0.5 asks Hugging Face for an engine wheel that is not published (3.0.2); fall back to 3.0.1."""
    if os.environ.get("NEEDLE3_LIB_PATH"):
        return
    lib = os.path.join(CACHE, "engine-3.0.1", "libneedle3.dylib")
    if not os.path.exists(lib):
        os.makedirs(os.path.dirname(lib), exist_ok=True)
        data = urllib.request.urlopen(ENGINE_FALLBACK, timeout=60).read()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for n in z.namelist():
                if n.endswith("libneedle3.dylib"):
                    open(lib, "wb").write(z.read(n)); break
    os.environ["NEEDLE3_LIB_PATH"] = lib

ensure_engine()
import needle  # noqa: E402

agent, agent_key = None, None

def get_agent(tools):
    global agent, agent_key
    key = hashlib.sha1(json.dumps(tools, sort_keys=True).encode()).hexdigest()
    if agent is None or key != agent_key:
        schemas = [{"name": t["name"], "description": (t.get("description") or "")[:300], "parameters": t.get("inputSchema") or t.get("parameters") or {"type": "object", "properties": {}}} for t in tools]
        agent = needle.Needle(tools=schemas, system=f"macOS assistant. Home folder is {os.path.expanduser('~')}.")
        agent_key = key
    return agent

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        self._send(200, {"status": "ok", "engine": "Needle 3", "loaded": agent is not None}) if self.path == "/health" else self._send(404, {"error": "not found"})
    def do_POST(self):
        if self.path != "/v1/route": return self._send(404, {"error": "not found"})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0")) or "{}"))
            q, tools = (req.get("query") or "").strip(), req.get("tools") or []
            if not q or not tools: return self._send(400, {"error": "query and tools required"})
            a = get_agent(tools); t0 = time.time(); r = a.complete(q); a.reset()
            self._send(200, {"calls": r.get("function_calls") or [], "suppressed": r.get("suppressed_calls") or [], "confidence": r.get("confidence") or 0,
                             "reasoning": r.get("reasoning") or "", "ms": int((time.time() - t0) * 1000), "engine": "Needle 3"})
        except Exception as e:  # never take Muon down with us
            self._send(500, {"error": str(e)[:300]})

if __name__ == "__main__":
    print(f"needle-serve on http://127.0.0.1:{PORT}  (engine {os.environ.get('NEEDLE3_LIB_PATH')})", flush=True)
    HTTPServer(("127.0.0.1", PORT), H).serve_forever()
