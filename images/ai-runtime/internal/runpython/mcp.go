// Package runpython is the platform MCP server behind the run_python tool:
// one agent-sandbox SandboxClaim per call, the agent's read tools reachable
// from the sandbox through the gateway, files returned as artifact URLs.
package runpython

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
)

const (
	mcpProtocolVersion = "2025-06-18"
	maxRequestBytes    = 1 << 20
)

// ToolDescription is what the model reads to learn code mode.
const ToolDescription = `Run Python 3.13 code in an isolated sandbox (no network except your own tools, 512 MiB, at most 60 s).
Your read-only tools are importable: ` + "`from cnp_tools import tools`" + `, then call ` + "`tools.<server>.<tool>(**args)`" + `,
for example ` + "`tools.epitweet.get_thread(post_id=\"42\")`" + `. ` + "`print(tools)`" + ` lists them with their arguments.
Results come back as Python objects (dicts, lists). pandas, numpy and matplotlib are installed.
Files written to the current directory (PNG, CSV, ...) are returned as artifacts with a URL valid 24 h; put those URLs in your answer.
Print what you need to see: only stdout and stderr come back to you.`

var inputSchema = json.RawMessage(`{
  "type": "object",
  "properties": {
    "code": {"type": "string", "description": "Python source to run."},
    "timeout_s": {"type": "integer", "minimum": 1, "maximum": 60, "default": 60, "description": "Wall-clock limit in seconds."}
  },
  "required": ["code"],
  "additionalProperties": false
}`)

// CodeRunner runs one run_python call on behalf of the caller's JWT.
type CodeRunner interface {
	Run(ctx context.Context, callerJWT, code string, timeoutS int) (*Result, error)
}

// MCPHandler serves the stateless streamable-HTTP MCP endpoint (JSON responses only).
type MCPHandler struct {
	Runner  CodeRunner
	Version string
	Log     *slog.Logger
}

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type textContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type callResult struct {
	Content           []textContent `json:"content"`
	StructuredContent any           `json:"structuredContent,omitempty"`
	IsError           bool          `json:"isError"`
}

func (h *MCPHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
	case http.MethodDelete:
		w.WriteHeader(http.StatusOK)
		return
	default:
		// Stateless server: no server-initiated stream on GET.
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, maxRequestBytes+1))
	if err != nil || len(body) > maxRequestBytes {
		http.Error(w, "request too large", http.StatusRequestEntityTooLarge)
		return
	}
	callerJWT := bearer(r.Header.Get("Authorization"))

	trimmed := strings.TrimSpace(string(body))
	if strings.HasPrefix(trimmed, "[") {
		var batch []rpcRequest
		if err := json.Unmarshal(body, &batch); err != nil {
			writeJSON(w, rpcResponse{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcError{Code: -32700, Message: "parse error"}})
			return
		}
		var out []rpcResponse
		for _, req := range batch {
			if resp, ok := h.handle(r.Context(), req, callerJWT); ok {
				out = append(out, resp)
			}
		}
		if len(out) == 0 {
			w.WriteHeader(http.StatusAccepted)
			return
		}
		writeJSON(w, out)
		return
	}
	var req rpcRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSON(w, rpcResponse{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcError{Code: -32700, Message: "parse error"}})
		return
	}
	resp, ok := h.handle(r.Context(), req, callerJWT)
	if !ok {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	writeJSON(w, resp)
}

// handle returns false for notifications, which get no response.
func (h *MCPHandler) handle(ctx context.Context, req rpcRequest, callerJWT string) (rpcResponse, bool) {
	if len(req.ID) == 0 || string(req.ID) == "null" {
		return rpcResponse{}, false
	}
	resp := rpcResponse{JSONRPC: "2.0", ID: req.ID}
	switch req.Method {
	case "initialize":
		var p struct {
			ProtocolVersion string `json:"protocolVersion"`
		}
		_ = json.Unmarshal(req.Params, &p)
		version := p.ProtocolVersion
		if version == "" {
			version = mcpProtocolVersion
		}
		resp.Result = map[string]any{
			"protocolVersion": version,
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": "run-python", "version": h.Version},
		}
	case "ping":
		resp.Result = map[string]any{}
	case "tools/list":
		resp.Result = map[string]any{"tools": []map[string]any{{
			"name":        "run_python",
			"description": ToolDescription,
			"inputSchema": inputSchema,
			"annotations": map[string]any{"readOnlyHint": true, "openWorldHint": false},
		}}}
	case "tools/call":
		resp.Result, resp.Error = h.call(ctx, req.Params, callerJWT)
	default:
		resp.Error = &rpcError{Code: -32601, Message: "method not found"}
	}
	return resp, true
}

func (h *MCPHandler) call(ctx context.Context, params json.RawMessage, callerJWT string) (any, *rpcError) {
	var p struct {
		Name      string `json:"name"`
		Arguments struct {
			Code     string `json:"code"`
			TimeoutS int    `json:"timeout_s"`
		} `json:"arguments"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, &rpcError{Code: -32602, Message: "invalid params"}
	}
	if p.Name != "run_python" {
		return nil, &rpcError{Code: -32602, Message: "unknown tool " + p.Name}
	}
	if strings.TrimSpace(p.Arguments.Code) == "" {
		return toolError("code is empty"), nil
	}
	if callerJWT == "" {
		return toolError("run_python needs the caller's token: call it through the AI gateway"), nil
	}
	res, err := h.Runner.Run(ctx, callerJWT, p.Arguments.Code, p.Arguments.TimeoutS)
	if err != nil {
		h.Log.Error("run_python failed", "err", err)
		var userErr *UserError
		if errors.As(err, &userErr) {
			return toolError(userErr.Msg), nil
		}
		return toolError("the sandbox could not run this code (platform error, try again later)"), nil
	}
	text, _ := json.Marshal(res)
	return callResult{Content: []textContent{{Type: "text", Text: string(text)}}, StructuredContent: res}, nil
}

func toolError(msg string) callResult {
	return callResult{Content: []textContent{{Type: "text", Text: msg}}, IsError: true}
}

func bearer(header string) string {
	scheme, token, ok := strings.Cut(header, " ")
	if !ok || !strings.EqualFold(scheme, "bearer") {
		return ""
	}
	return strings.TrimSpace(token)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}
