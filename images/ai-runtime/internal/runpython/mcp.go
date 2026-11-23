// Package runpython is the platform MCP server behind the run_python tool:
// one agent-sandbox SandboxClaim per call, the agent's read tools reachable
// from the sandbox through the gateway, files returned as artifact URLs.
package runpython

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/mcp"
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

// MCPHandler serves the run_python tool over MCP.
type MCPHandler struct {
	Runner  CodeRunner
	Version string
	Log     *slog.Logger
}

func (h *MCPHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	(&mcp.Server{
		Name:    "run-python",
		Version: h.Version,
		Tool: mcp.Tool{
			Name:        "run_python",
			Description: ToolDescription,
			InputSchema: inputSchema,
			Annotations: map[string]any{"readOnlyHint": true, "openWorldHint": false},
		},
		Call:          h.call,
		PlatformError: "the sandbox could not run this code (platform error, try again later)",
		Log:           h.Log,
	}).ServeHTTP(w, r)
}

func (h *MCPHandler) call(ctx context.Context, callerJWT string, arguments json.RawMessage) (any, error) {
	var args struct {
		Code     string `json:"code"`
		TimeoutS int    `json:"timeout_s"`
	}
	if err := json.Unmarshal(arguments, &args); err != nil {
		return nil, &mcp.ToolError{Msg: "invalid arguments: " + err.Error()}
	}
	if strings.TrimSpace(args.Code) == "" {
		return nil, &mcp.ToolError{Msg: "code is empty"}
	}
	if callerJWT == "" {
		return nil, &mcp.ToolError{Msg: "run_python needs the caller's token: call it through the AI gateway"}
	}
	res, err := h.Runner.Run(ctx, callerJWT, args.Code, args.TimeoutS)
	var userErr *UserError
	if errors.As(err, &userErr) {
		return nil, &mcp.ToolError{Msg: userErr.Msg}
	}
	if err != nil {
		return nil, err
	}
	return res, nil
}
