"""budget-guard: the platform-wide AI spend cap, made readable.

The gateway debits every LLM call (llm.cost plus web searches, in micro-USD)
from the ratelimit descriptor platform=all, which blocks on its own once the
cap is reached but answers an empty 429, and whose window rolls over every
365 days. This loop:
  - copies each window's counter to a key that never expires, so the spend
    stays cumulative until an admin resets it;
  - exports the spend and the cap for the recording rules
    cnp:ai_global_spend_usd / cnp:ai_global_budget_usd (alerts at 80 and 100 %);
  - at 100 % applies AgentgatewayPolicy ai-budget-exhausted, a JSON 429 that
    says why, and removes it once the cap is raised or the spend reset.
"""

import http.server
import json
import os
import socket
import ssl
import threading
import time
import urllib.error
import urllib.request

REDIS_HOST = os.environ.get("REDIS_HOST", "ratelimit-redis")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
WINDOW_PREFIX = os.environ.get("WINDOW_PREFIX", "ai-budget_platform_all_")
LEDGER_PREFIX = os.environ.get("LEDGER_PREFIX", "cnp:ai-spend:window:")
CAP_USD = float(os.environ["CAP_USD"])
INTERVAL_S = float(os.environ.get("INTERVAL_S", "15"))
NAMESPACE = os.environ.get("POD_NAMESPACE", "ai-gateway")
GATEWAY = os.environ.get("GATEWAY_NAME", "ai-gateway")
POLICY_NAME = "ai-budget-exhausted"
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9090"))

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
API = "https://kubernetes.default.svc"
POLICIES = f"{API}/apis/agentgateway.dev/v1alpha1/namespaces/{NAMESPACE}/agentgatewaypolicies"

EXHAUSTED_BODY = json.dumps(
    {
        "error": "ai_budget_exhausted",
        "message": f"Budget IA de la plateforme atteint ({CAP_USD:g} $). Contactez un admin plateforme.",
    },
    ensure_ascii=False,
)


def redis_command(*args: str) -> object:
    payload = f"*{len(args)}\r\n" + "".join(f"${len(a.encode())}\r\n{a}\r\n" for a in args)
    with socket.create_connection((REDIS_HOST, REDIS_PORT), timeout=5) as sock:
        sock.sendall(payload.encode())
        reader = sock.makefile("rb")
        return _read_reply(reader)


def _read_reply(reader) -> object:
    line = reader.readline().rstrip(b"\r\n")
    kind, rest = line[:1], line[1:]
    if kind == b"+":
        return rest.decode()
    if kind == b"-":
        raise RuntimeError(f"redis: {rest.decode()}")
    if kind == b":":
        return int(rest)
    if kind == b"$":
        size = int(rest)
        if size < 0:
            return None
        data = reader.read(size + 2)[:-2]
        return data.decode()
    if kind == b"*":
        return [_read_reply(reader) for _ in range(int(rest))]
    raise RuntimeError(f"redis: unexpected reply {line!r}")


def cumulative_spend_micro_usd() -> int:
    for key in redis_command("KEYS", WINDOW_PREFIX + "*"):
        value = redis_command("GET", key)
        if value is not None:
            redis_command("SET", LEDGER_PREFIX + key[len(WINDOW_PREFIX):], value)
    total = 0
    for key in redis_command("KEYS", LEDGER_PREFIX + "*"):
        value = redis_command("GET", key)
        total += int(value or 0)
    return total


def kube(method: str, url: str, body: dict | None = None) -> int:
    with open(f"{SA_DIR}/token") as f:
        token = f.read().strip()
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Content-Type", "application/json")
    context = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")
    try:
        with urllib.request.urlopen(request, context=context, timeout=10) as response:
            return response.status
    except urllib.error.HTTPError as err:
        return err.code


def exhausted_policy() -> dict:
    return {
        "apiVersion": "agentgateway.dev/v1alpha1",
        "kind": "AgentgatewayPolicy",
        "metadata": {
            "name": POLICY_NAME,
            "namespace": NAMESPACE,
            "labels": {"app.kubernetes.io/managed-by": "budget-guard"},
        },
        "spec": {
            "targetRefs": [
                {"group": "gateway.networking.k8s.io", "kind": "Gateway", "name": GATEWAY}
            ],
            "traffic": {
                "directResponse": {
                    "conditional": [
                        {
                            "condition": 'request.path.startsWith("/v1/messages") || request.path.startsWith("/a2a/")',
                            "policy": {
                                "status": 429,
                                "body": EXHAUSTED_BODY,
                                "headers": [
                                    {"name": "content-type", "value": '"application/json"'},
                                    {"name": "x-cnp-refusal", "value": '"budget"'},
                                ],
                            },
                        }
                    ]
                }
            },
        },
    }


def set_exhausted(exhausted: bool) -> None:
    url = f"{POLICIES}/{POLICY_NAME}"
    present = kube("GET", url) == 200
    if exhausted and not present:
        status = kube("POST", POLICIES, exhausted_policy())
        if status not in (200, 201, 409):
            raise RuntimeError(f"create {POLICY_NAME}: HTTP {status}")
        log("budget exhausted: 429 policy applied")
    elif not exhausted and present:
        status = kube("DELETE", url)
        if status not in (200, 202, 404):
            raise RuntimeError(f"delete {POLICY_NAME}: HTTP {status}")
        log("budget below cap: 429 policy removed")


class State:
    spend_usd = 0.0
    exhausted = 0
    last_success = 0.0
    errors = 0


def metrics_text() -> str:
    return (
        "# TYPE cnp_ai_global_spend_usd gauge\n"
        f"cnp_ai_global_spend_usd {State.spend_usd}\n"
        "# TYPE cnp_ai_global_budget_usd gauge\n"
        f"cnp_ai_global_budget_usd {CAP_USD}\n"
        "# TYPE cnp_ai_budget_guard_exhausted gauge\n"
        f"cnp_ai_budget_guard_exhausted {State.exhausted}\n"
        "# TYPE cnp_ai_budget_guard_last_success_timestamp_seconds gauge\n"
        f"cnp_ai_budget_guard_last_success_timestamp_seconds {State.last_success}\n"
        "# TYPE cnp_ai_budget_guard_errors_total counter\n"
        f"cnp_ai_budget_guard_errors_total {State.errors}\n"
    )


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/metrics":
            body = metrics_text().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
        elif self.path == "/healthz":
            healthy = time.time() - State.last_success < 5 * INTERVAL_S
            body = b"ok" if healthy else b"stale"
            self.send_response(200 if healthy else 503)
        else:
            body = b"not found"
            self.send_response(404)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args) -> None:
        pass


def log(message: str) -> None:
    print(json.dumps({"ts": time.time(), "msg": message}), flush=True)


def main() -> None:
    server = http.server.ThreadingHTTPServer(("", METRICS_PORT), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log(f"budget-guard started, cap {CAP_USD:g} USD")
    while True:
        try:
            spend_usd = cumulative_spend_micro_usd() / 1_000_000
            exhausted = spend_usd >= CAP_USD
            set_exhausted(exhausted)
            State.spend_usd, State.exhausted, State.last_success = spend_usd, int(exhausted), time.time()
        except Exception as err:  # noqa: BLE001 - keep looping, /healthz goes stale and alerts
            State.errors += 1
            log(f"error: {err}")
        time.sleep(INTERVAL_S)


if __name__ == "__main__":
    main()
