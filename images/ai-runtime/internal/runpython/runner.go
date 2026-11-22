package runpython

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"path"
	"regexp"
	"strings"
	"time"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/oidc"
)

const (
	// IsolationLabel on an agent's namespace raises its sandboxes to Kata.
	IsolationLabel = "cnp.3istor.com/isolation"

	maxTimeoutS      = 60
	maxArtifacts     = 10
	maxArtifactBytes = 5 << 20
)

var artifactName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`)

// UserError is a failure the model can act on; anything else is a platform error.
type UserError struct{ Msg string }

func (e *UserError) Error() string { return e.Msg }

// Artifact is a file the code wrote, as the caller sees it.
type Artifact struct {
	Name string `json:"name"`
	Mime string `json:"mime"`
	URL  string `json:"url"`
	Size int    `json:"size"`
}

// Result is the run_python tool output.
type Result struct {
	Stdout     string     `json:"stdout"`
	Stderr     string     `json:"stderr"`
	ExitCode   int        `json:"exit_code"`
	Artifacts  []Artifact `json:"artifacts"`
	Runtime    string     `json:"runtime"`
	DurationMs int64      `json:"duration_ms"`
}

// Sandboxes hands out a ready sandbox for one run and frees it afterwards.
type Sandboxes interface {
	Acquire(ctx context.Context, template, name string, labels map[string]string) (claim, endpoint string, err error)
	Release(ctx context.Context, claim string) error
	NamespaceLabel(ctx context.Context, namespace, label string) (string, error)
}

// Exchanger trades the caller's JWT for the sandbox's read-only one.
type Exchanger interface {
	Exchange(ctx context.Context, subjectToken, audience, scope string) (oidc.Token, error)
}

// Store keeps artifacts for the /ai-artifacts/ route.
type Store interface {
	Put(ctx context.Context, key, contentType string, data []byte) error
}

// Runner implements CodeRunner.
type Runner struct {
	Sandboxes Sandboxes
	Exchanger Exchanger
	Store     Store
	HTTP      *http.Client
	// GatewayURL is the in-cluster AI gateway base URL the sandbox calls.
	GatewayURL string
	// Templates maps isolation to SandboxTemplate (and warm pool) name.
	Templates map[string]string
	Log       *slog.Logger
	Now       func() time.Time
}

type caller struct {
	project, agent string
}

func callerOf(jwt string) (caller, error) {
	claims, err := oidc.UnverifiedClaims(jwt)
	if err != nil {
		return caller{}, err
	}
	c := caller{project: stringClaim(claims["project"]), agent: stringClaim(claims["azp"])}
	if c.project == "" || c.agent == "" {
		return caller{}, &UserError{Msg: "the caller's token has no project or azp claim"}
	}
	return c, nil
}

// stringClaim accepts "p", "/p" and ["p"]: Keycloak's group mapper emits paths in a list.
func stringClaim(v any) string {
	switch x := v.(type) {
	case string:
		return strings.TrimPrefix(x, "/")
	case []any:
		if len(x) == 1 {
			return stringClaim(x[0])
		}
	}
	return ""
}

// isolationOf reads the isolation of the calling agent's namespace
// (<project>-<agent>, client id agent-<project>-<agent>).
func (r *Runner) isolationOf(ctx context.Context, c caller) string {
	agent, ok := strings.CutPrefix(c.agent, "agent-"+c.project+"-")
	if !ok {
		return "gvisor"
	}
	iso, err := r.Sandboxes.NamespaceLabel(ctx, c.project+"-"+agent, IsolationLabel)
	if err != nil {
		r.Log.Warn("isolation lookup failed, using gvisor", "err", err)
		return "gvisor"
	}
	if iso == "kata" {
		return "kata"
	}
	return "gvisor"
}

type execRequest struct {
	Code     string `json:"code"`
	Token    string `json:"token"`
	MCPURL   string `json:"mcp_url"`
	TimeoutS int    `json:"timeout_s"`
}

type execArtifact struct {
	Name string `json:"name"`
	Data string `json:"b64"`
}

type execResponse struct {
	ExitCode  int            `json:"exit_code"`
	Stdout    string         `json:"stdout"`
	Stderr    string         `json:"stderr"`
	Artifacts []execArtifact `json:"artifacts"`
}

// Run executes code in a fresh sandbox.
func (r *Runner) Run(ctx context.Context, callerJWT, code string, timeoutS int) (*Result, error) {
	start := r.Now()
	if timeoutS <= 0 || timeoutS > maxTimeoutS {
		timeoutS = maxTimeoutS
	}
	c, err := callerOf(callerJWT)
	if err != nil {
		return nil, err
	}
	sandboxToken, err := r.Exchanger.Exchange(ctx, callerJWT, "ai-gateway", "mcp-read")
	if err != nil {
		return nil, fmt.Errorf("token exchange: %w", err)
	}
	isolation := r.isolationOf(ctx, c)
	task := newTaskID()
	labels := map[string]string{"cnp.3istor.com/project": c.project, "cnp.3istor.com/agent": c.agent, "cnp.3istor.com/task": task}
	claim, endpoint, err := r.Sandboxes.Acquire(ctx, r.Templates[isolation], "run-"+task[:20], labels)
	if claim != "" {
		defer func() {
			// The caller may have gone: free the sandbox anyway.
			releaseCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 15*time.Second)
			defer cancel()
			if err := r.Sandboxes.Release(releaseCtx, claim); err != nil {
				r.Log.Error("sandbox release failed", "claim", claim, "err", err)
			}
		}()
	}
	if err != nil {
		return nil, fmt.Errorf("sandbox: %w", err)
	}

	out, err := r.exec(ctx, endpoint, execRequest{
		Code: code, Token: sandboxToken.AccessToken, TimeoutS: timeoutS,
		MCPURL: strings.TrimRight(r.GatewayURL, "/") + "/mcp/" + c.project,
	})
	if err != nil {
		return nil, err
	}
	artifacts, err := r.storeArtifacts(ctx, task, out.Artifacts)
	if err != nil {
		return nil, err
	}
	// Who ran it is on the gateway's traces and the SandboxClaim labels; logs keep the task only.
	r.Log.Info("run_python done", "task", task, "runtime", isolation,
		"exit_code", out.ExitCode, "artifacts", len(artifacts), "duration_ms", r.Now().Sub(start).Milliseconds())
	return &Result{
		Stdout: out.Stdout, Stderr: out.Stderr, ExitCode: out.ExitCode, Artifacts: artifacts,
		Runtime: isolation, DurationMs: r.Now().Sub(start).Milliseconds(),
	}, nil
}

func (r *Runner) exec(ctx context.Context, endpoint string, req execRequest) (*execResponse, error) {
	body, _ := json.Marshal(req)
	ctx, cancel := context.WithTimeout(ctx, time.Duration(req.TimeoutS+30)*time.Second)
	defer cancel()
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/run", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := r.HTTP.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("sandbox exec: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		msg, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		return nil, fmt.Errorf("sandbox exec answered %d: %s", resp.StatusCode, msg)
	}
	var out execResponse
	if err := json.NewDecoder(io.LimitReader(resp.Body, 64<<20)).Decode(&out); err != nil {
		return nil, fmt.Errorf("sandbox exec response: %w", err)
	}
	return &out, nil
}

func (r *Runner) storeArtifacts(ctx context.Context, task string, files []execArtifact) ([]Artifact, error) {
	artifacts := []Artifact{}
	for _, f := range files {
		if len(artifacts) == maxArtifacts {
			break
		}
		if !artifactName.MatchString(f.Name) {
			continue
		}
		data, err := base64.StdEncoding.DecodeString(f.Data)
		if err != nil || len(data) == 0 || len(data) > maxArtifactBytes {
			continue
		}
		mt := artifactMime(f.Name)
		key := task + "/" + f.Name
		if err := r.Store.Put(ctx, key, mt, data); err != nil {
			return nil, fmt.Errorf("store artifact %s: %w", key, err)
		}
		artifacts = append(artifacts, Artifact{Name: f.Name, Mime: mt, URL: ArtifactRoute + key, Size: len(data)})
	}
	return artifacts, nil
}

func artifactMime(name string) string {
	if mt, ok := inlineTypes[strings.ToLower(path.Ext(name))]; ok {
		return mt
	}
	if mt := mime.TypeByExtension(path.Ext(name)); mt != "" {
		return mt
	}
	return "application/octet-stream"
}

func newTaskID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
