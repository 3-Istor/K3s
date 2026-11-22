"""The calling agent's read-only tools, generated from the AI gateway's MCP tool list.

    from cnp_tools import tools
    print(tools)                                   # every tool with its arguments
    thread = tools.epitweet.get_thread(post_id="42")

Gateway tool names are ``<server>__<tool>``: ``tools.<server>.<tool>(**args)``. Every call goes
through the gateway with the sandbox's short-lived read-only token, so the per-tool policy,
budgets and traces of the agent apply to code exactly as to direct tool calls.
"""

import json
import os
import urllib.error
import urllib.request

__all__ = ["tools", "ToolError"]

_PROTOCOL_VERSION = "2025-06-18"
_HIDDEN = {"run_python"}
_JSON_TYPES = {"string": "str", "integer": "int", "number": "float", "boolean": "bool", "array": "list", "object": "dict"}


class ToolError(RuntimeError):
    """The gateway or the tool refused or failed the call."""


def _rpc(method, params, _ids=iter(range(1, 1 << 31))):
    url, token = os.environ["CNP_MCP_URL"], os.environ["CNP_MCP_TOKEN"]
    body = json.dumps({"jsonrpc": "2.0", "id": next(_ids), "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "content-type": "application/json",
        "accept": "application/json, text/event-stream",
        "authorization": "Bearer " + token,
        "mcp-protocol-version": _PROTOCOL_VERSION,
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        raise ToolError(f"{method} refused by the gateway (HTTP {e.code}): {detail}") from None
    if raw.lstrip().startswith(("event:", "data:")):
        raw = next(line[5:] for line in raw.splitlines() if line.startswith("data:"))
    msg = json.loads(raw)
    if "error" in msg:
        raise ToolError(msg["error"].get("message", "tool call failed"))
    return msg["result"]


def _decode(result):
    if result.get("structuredContent") is not None:
        return result["structuredContent"]
    text = "".join(c.get("text", "") for c in result.get("content", []) if c.get("type") == "text")
    if result.get("isError"):
        raise ToolError(text or "tool call failed")
    try:
        return json.loads(text)
    except ValueError:
        return text


def _signature(schema):
    props = (schema or {}).get("properties") or {}
    required = set((schema or {}).get("required") or [])
    args = []
    for name, spec in props.items():
        kind = _JSON_TYPES.get(spec.get("type"), "Any")
        args.append(f"{name}: {kind}" if name in required else f"{name}: {kind} = None")
    return ", ".join(args)


class _Tool:
    def __init__(self, full_name, short_name, description, schema):
        self._full_name = full_name
        self.__name__ = short_name
        self._schema = schema or {}
        self.__doc__ = f"{short_name}({_signature(schema)})\n\n{description or ''}".strip()

    def __call__(self, **arguments):
        props = self._schema.get("properties")
        if props is not None:
            unknown = set(arguments) - set(props)
            if unknown:
                raise TypeError(f"{self.__name__}() got unknown arguments {sorted(unknown)}; expected {sorted(props)}")
        missing = set(self._schema.get("required") or []) - set(arguments)
        if missing:
            raise TypeError(f"{self.__name__}() missing required arguments {sorted(missing)}")
        return _decode(_rpc("tools/call", {"name": self._full_name, "arguments": arguments}))

    def __repr__(self):
        return f"{self.__name__}({_signature(self._schema)})"


class _Server:
    def __init__(self, name):
        self._name = name
        self._tools = {}

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        try:
            return self._tools[name]
        except KeyError:
            raise AttributeError(f"server {self._name!r} has no tool {name!r}; it has {sorted(self._tools)}") from None

    def __dir__(self):
        return sorted(self._tools)

    def __repr__(self):
        return "\n".join(f"tools.{self._name}.{t!r}" for t in self._tools.values())


class _Tools:
    def __init__(self):
        self._servers = None

    def _load(self):
        if self._servers is None:
            servers = {}
            for t in _rpc("tools/list", {}).get("tools", []):
                full = t["name"]
                server, sep, short = full.partition("__")
                if not sep:
                    server, short = "platform", full
                if short in _HIDDEN:
                    continue
                srv = servers.setdefault(server, _Server(server))
                srv._tools[short] = _Tool(full, short, t.get("description"), t.get("inputSchema"))
            self._servers = servers
        return self._servers

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        servers = self._load()
        try:
            return servers[name]
        except KeyError:
            raise AttributeError(f"no tool server {name!r}; available: {sorted(servers)}") from None

    def __dir__(self):
        return sorted(self._load())

    def __repr__(self):
        servers = self._load()
        if not servers:
            return "(no tools available to this agent)"
        return "\n".join(repr(s) for s in servers.values())


tools = _Tools()
