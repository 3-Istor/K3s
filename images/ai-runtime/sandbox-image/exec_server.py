"""Runs model-written Python inside the sandbox pod for run-python.

POST /run {code, token, mcp_url, timeout_s} -> {exit_code, stdout, stderr, artifacts: [{name, b64}]}.
One request = one subprocess in a fresh directory; files left there are the artifacts.
"""

import base64
import json
import os
import shutil
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

WORKSPACE = os.environ.get("WORKSPACE", "/workspace")
MAX_OUTPUT = 16_000
MAX_ARTIFACTS = 10
MAX_ARTIFACT_BYTES = 5 * 1024 * 1024
MAX_TIMEOUT_S = 60
# matplotlib wants a writable config dir; the image ships a prebuilt font cache in /opt/mpl.
MPL_DIR = "/tmp/mpl"


def run(req):
    out_dir = tempfile.mkdtemp(prefix="run-", dir=WORKSPACE)
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/tmp",
        "MPLBACKEND": "Agg",
        "MPLCONFIGDIR": MPL_DIR,
        "PYTHONUNBUFFERED": "1",
        "CNP_MCP_URL": req["mcp_url"],
        "CNP_MCP_TOKEN": req["token"],
    }
    timeout = max(1, min(int(req.get("timeout_s") or MAX_TIMEOUT_S), MAX_TIMEOUT_S))
    try:
        p = subprocess.run(["python", "-c", req["code"]], cwd=out_dir, env=env, capture_output=True, text=True, timeout=timeout)
        res = {"exit_code": p.returncode, "stdout": p.stdout[-MAX_OUTPUT:], "stderr": p.stderr[-MAX_OUTPUT:]}
    except subprocess.TimeoutExpired as e:
        stdout = (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or "")
        res = {"exit_code": 124, "stdout": stdout[-MAX_OUTPUT:], "stderr": f"timeout: the code ran longer than {timeout} s"}
    res["artifacts"] = collect(out_dir)
    return res


def collect(out_dir):
    artifacts = []
    for name in sorted(os.listdir(out_dir)):
        path = os.path.join(out_dir, name)
        if len(artifacts) == MAX_ARTIFACTS or not os.path.isfile(path) or os.path.islink(path):
            continue
        if os.path.getsize(path) > MAX_ARTIFACT_BYTES:
            continue
        with open(path, "rb") as f:
            artifacts.append({"name": name, "b64": base64.b64encode(f.read()).decode()})
    return artifacts


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._send(200, {"ok": True})

    def do_POST(self):
        if self.path != "/run":
            return self._send(404, {"error": "not found"})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("content-length") or 0)))
            for key in ("code", "token", "mcp_url"):
                if not isinstance(req.get(key), str):
                    raise ValueError(f"{key} is required")
        except ValueError as e:
            return self._send(400, {"error": str(e)})
        self._send(200, run(req))


if __name__ == "__main__":
    if os.path.isdir("/opt/mpl"):
        shutil.copytree("/opt/mpl", MPL_DIR, dirs_exist_ok=True)
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8888"))), Handler).serve_forever()
