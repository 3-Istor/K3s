// Package mcp serves one platform tool over stateless streamable-HTTP MCP
// (JSON responses only), the transport the AI gateway's MCP targets speak.
package mcp

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
	protocolVersion = "2025-06-18"
	maxRequestBytes = 1 << 20
)

// Tool is what tools/list publishes. Name is final: the gateway adds no prefix.
type Tool struct {
	Name        string
	Description string
	InputSchema json.RawMessage
	Annotations map[string]any
}

// ToolError is a failure the model can act on; its message is shown as is.
type ToolError struct{ Msg string }

func (e *ToolError) Error() string { return e.Msg }

// CallFunc runs one tools/call with the caller's bearer token ("" when absent).
type CallFunc func(ctx context.Context, callerJWT string, arguments json.RawMessage) (any, error)

// Server answers initialize, ping, tools/list and tools/call for Tool.
type Server struct {
	Name    string
	Version string
	Tool    Tool
	Call    CallFunc
	// PlatformError replaces any error that is not a *ToolError, so internal
	// details never reach the model.
	PlatformError string
	Log           *slog.Logger
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

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
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

	if strings.HasPrefix(strings.TrimSpace(string(body)), "[") {
		var batch []rpcRequest
		if err := json.Unmarshal(body, &batch); err != nil {
			writeJSON(w, parseError())
			return
		}
		var out []rpcResponse
		for _, req := range batch {
			if resp, ok := s.handle(r.Context(), req, callerJWT); ok {
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
		writeJSON(w, parseError())
		return
	}
	resp, ok := s.handle(r.Context(), req, callerJWT)
	if !ok {
		w.WriteHeader(http.StatusAccepted)
		return
	}
	writeJSON(w, resp)
}

// handle returns false for notifications, which get no response.
func (s *Server) handle(ctx context.Context, req rpcRequest, callerJWT string) (rpcResponse, bool) {
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
			version = protocolVersion
		}
		resp.Result = map[string]any{
			"protocolVersion": version,
			"capabilities":    map[string]any{"tools": map[string]any{"listChanged": false}},
			"serverInfo":      map[string]any{"name": s.Name, "version": s.Version},
		}
	case "ping":
		resp.Result = map[string]any{}
	case "tools/list":
		resp.Result = map[string]any{"tools": []map[string]any{{
			"name":        s.Tool.Name,
			"description": s.Tool.Description,
			"inputSchema": s.Tool.InputSchema,
			"annotations": s.Tool.Annotations,
		}}}
	case "tools/call":
		resp.Result, resp.Error = s.call(ctx, req.Params, callerJWT)
	default:
		resp.Error = &rpcError{Code: -32601, Message: "method not found"}
	}
	return resp, true
}

func (s *Server) call(ctx context.Context, params json.RawMessage, callerJWT string) (any, *rpcError) {
	var p struct {
		Name      string          `json:"name"`
		Arguments json.RawMessage `json:"arguments"`
	}
	if err := json.Unmarshal(params, &p); err != nil {
		return nil, &rpcError{Code: -32602, Message: "invalid params"}
	}
	if p.Name != s.Tool.Name {
		return nil, &rpcError{Code: -32602, Message: "unknown tool " + p.Name}
	}
	if len(p.Arguments) == 0 {
		p.Arguments = json.RawMessage("{}")
	}
	res, err := s.Call(ctx, callerJWT, p.Arguments)
	if err != nil {
		var toolErr *ToolError
		if errors.As(err, &toolErr) {
			return toolError(toolErr.Msg), nil
		}
		s.Log.Error(s.Tool.Name+" failed", "err", err)
		return toolError(s.PlatformError), nil
	}
	text, _ := json.Marshal(res)
	return callResult{Content: []textContent{{Type: "text", Text: string(text)}}, StructuredContent: res}, nil
}

func toolError(msg string) callResult {
	return callResult{Content: []textContent{{Type: "text", Text: msg}}, IsError: true}
}

func parseError() rpcResponse {
	return rpcResponse{JSONRPC: "2.0", ID: json.RawMessage("null"), Error: &rpcError{Code: -32700, Message: "parse error"}}
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
