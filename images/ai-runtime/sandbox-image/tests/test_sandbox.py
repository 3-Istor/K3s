import json
import os
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import exec_server  # noqa: E402

TOOLS = [
    {"name": "epitweet__get_thread", "description": "A thread.",
     "inputSchema": {"type": "object", "properties": {"post_id": {"type": "string"}}, "required": ["post_id"]}},
    {"name": "epitweet__reply_as_grok", "description": "Write tool.", "inputSchema": {"type": "object", "properties": {}}},
    {"name": "run_python", "description": "Itself.", "inputSchema": {"type": "object"}},
]


class FakeGateway(BaseHTTPRequestHandler):
    calls = []

    def log_message(self, *args):
        pass

    def do_POST(self):
        msg = json.loads(self.rfile.read(int(self.headers["content-length"])))
        FakeGateway.calls.append((self.headers["authorization"], msg))
        if msg["method"] == "tools/list":
            result = {"tools": TOOLS}
        elif msg["params"]["name"] == "epitweet__reply_as_grok":
            body = b'{"error":"tool not allowed for scope mcp-read"}'
            self.send_response(403)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        else:
            result = {"content": [{"type": "text", "text": json.dumps({"id": msg["params"]["arguments"]["post_id"], "likes": 3})}]}
        body = ("event: message\ndata: " + json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": result}) + "\n\n").encode()
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class SandboxTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gateway = ThreadingHTTPServer(("127.0.0.1", 0), FakeGateway)
        threading.Thread(target=cls.gateway.serve_forever, daemon=True).start()
        cls.workspace = tempfile.mkdtemp()
        exec_server.WORKSPACE = cls.workspace
        os.environ["PYTHONPATH"] = os.path.join(os.path.dirname(__file__), "..")

    @classmethod
    def tearDownClass(cls):
        cls.gateway.shutdown()

    def run_code(self, code, timeout_s=20):
        FakeGateway.calls.clear()
        url = f"http://127.0.0.1:{self.gateway.server_address[1]}/mcp/epitweet"
        req = {"code": code, "token": "sandbox-token", "mcp_url": url, "timeout_s": timeout_s}
        # The sandbox subprocess only sees PATH, so the package must be importable from cwd or site-packages.
        prelude = f"import sys; sys.path.insert(0, {os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')!r})\n"
        req["code"] = prelude + code
        return exec_server.run(req)

    def test_generated_module_calls_read_tool_with_sandbox_token(self):
        res = self.run_code("from cnp_tools import tools\nprint(tools.epitweet.get_thread(post_id='42')['likes'])")

        self.assertEqual(res["stdout"].strip(), "3", res["stderr"])
        self.assertEqual(FakeGateway.calls[-1][0], "Bearer sandbox-token")

    def test_listing_hides_run_python_and_shows_signatures(self):
        res = self.run_code("from cnp_tools import tools\nprint(tools)")

        self.assertIn("tools.epitweet.get_thread(post_id: str)", res["stdout"])
        self.assertNotIn("run_python", res["stdout"])

    def test_refused_tool_raises_tool_error(self):
        res = self.run_code(
            "from cnp_tools import tools, ToolError\n"
            "try:\n    tools.epitweet.reply_as_grok()\nexcept ToolError as e:\n    print('refused', e)")

        self.assertIn("refused", res["stdout"])
        self.assertIn("403", res["stdout"])

    def test_missing_argument_is_a_type_error_before_any_call(self):
        res = self.run_code("from cnp_tools import tools\ntools.epitweet.get_thread()")

        self.assertNotEqual(res["exit_code"], 0)
        self.assertIn("missing required arguments ['post_id']", res["stderr"])

    def test_files_in_working_directory_come_back_as_artifacts(self):
        res = self.run_code("open('data.csv', 'w').write('a,b\\n1,2\\n')")

        self.assertEqual([a["name"] for a in res["artifacts"]], ["data.csv"])

    def test_timeout_stops_the_code(self):
        res = self.run_code("import time; time.sleep(5)", timeout_s=1)

        self.assertEqual(res["exit_code"], 124)


if __name__ == "__main__":
    unittest.main()
