package runpython

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/oidc"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

func jwt(claims string) string {
	return "h." + base64.RawURLEncoding.EncodeToString([]byte(claims)) + ".s"
}

type fakeSandboxes struct {
	mu        sync.Mutex
	endpoint  string
	nsLabels  map[string]string
	templates []string
	released  []string
	labels    map[string]string
	acquireFn func() error
}

func (f *fakeSandboxes) Acquire(_ context.Context, template string, labels map[string]string) (string, string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.templates = append(f.templates, template)
	f.labels = labels
	if f.acquireFn != nil {
		return "claim-1", "", f.acquireFn()
	}
	return "claim-1", f.endpoint, nil
}

func (f *fakeSandboxes) Release(_ context.Context, claim string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.released = append(f.released, claim)
	return nil
}

func (f *fakeSandboxes) NamespaceLabel(_ context.Context, ns, _ string) (string, error) {
	return f.nsLabels[ns], nil
}

type fakeExchanger struct{ subject, scope string }

func (f *fakeExchanger) Exchange(_ context.Context, subject, _, scope string) (oidc.Token, error) {
	f.subject, f.scope = subject, scope
	return oidc.Token{AccessToken: "sandbox-token", Expiry: time.Now().Add(5 * time.Minute)}, nil
}

type memStore struct {
	mu      sync.Mutex
	objects map[string][]byte
	types   map[string]string
	at      time.Time
}

func newMemStore() *memStore {
	return &memStore{objects: map[string][]byte{}, types: map[string]string{}, at: time.Now()}
}

func (m *memStore) Put(_ context.Context, key, ct string, data []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.objects[key], m.types[key] = data, ct
	return nil
}

func (m *memStore) Get(_ context.Context, key string) (*Object, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	data, ok := m.objects[key]
	if !ok {
		return nil, ErrNotFound
	}
	return &Object{Body: io.NopCloser(bytes.NewReader(data)), Size: int64(len(data)), LastModified: m.at}, nil
}

// sandboxExec plays the exec server of the sandbox image.
func sandboxExec(t *testing.T, got *execRequest, resp execResponse) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewDecoder(r.Body).Decode(got)
		_ = json.NewEncoder(w).Encode(resp)
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func newRunner(sb *fakeSandboxes, ex *fakeExchanger, store Store) *Runner {
	return &Runner{
		Sandboxes: sb, Exchanger: ex, Store: store, HTTP: http.DefaultClient,
		GatewayURL: "http://gw:8080", Templates: map[string]string{"gvisor": "python", "kata": "python-kata"},
		Log: quiet, Now: time.Now,
	}
}

const readerJWT = `{"azp":"agent-epitweet-grok-reader","project":["/epitweet"]}`

func TestRun_GivesSandboxExchangedTokenAndProjectMCPRoute(t *testing.T) {
	t.Parallel()
	var got execRequest
	sb := &fakeSandboxes{endpoint: sandboxExec(t, &got, execResponse{Stdout: "ok\n"})}
	ex := &fakeExchanger{}
	caller := jwt(readerJWT)

	res, err := newRunner(sb, ex, newMemStore()).Run(context.Background(), caller, "print('ok')", 0)

	if err != nil {
		t.Fatal(err)
	}
	if ex.subject != caller || ex.scope != "mcp-read" || got.Token != "sandbox-token" ||
		got.MCPURL != "http://gw:8080/mcp/epitweet" || got.TimeoutS != 60 || res.Stdout != "ok\n" {
		t.Fatalf("exchange %+v, exec %+v, result %+v", ex, got, res)
	}
}

func TestRun_ReleasesSandbox_EvenWhenItNeverBecomesReady(t *testing.T) {
	t.Parallel()
	sb := &fakeSandboxes{acquireFn: func() error { return errors.New("not ready") }}

	_, err := newRunner(sb, &fakeExchanger{}, newMemStore()).Run(context.Background(), jwt(readerJWT), "1", 5)

	if err == nil || len(sb.released) != 1 {
		t.Fatalf("err %v, released %v", err, sb.released)
	}
}

func TestRun_UsesKataTemplate_WhenAgentNamespaceIsKata(t *testing.T) {
	t.Parallel()
	var got execRequest
	sb := &fakeSandboxes{endpoint: sandboxExec(t, &got, execResponse{}), nsLabels: map[string]string{"epitweet-grok-reader": "kata"}}

	res, err := newRunner(sb, &fakeExchanger{}, newMemStore()).Run(context.Background(), jwt(readerJWT), "1", 5)

	if err != nil || sb.templates[0] != "python-kata" || res.Runtime != "kata" {
		t.Fatalf("templates %v, result %+v, err %v", sb.templates, res, err)
	}
}

func TestRun_ReturnsArtifactURLs_AndStoresFiles(t *testing.T) {
	t.Parallel()
	var got execRequest
	png := []byte("\x89PNG fake")
	sb := &fakeSandboxes{endpoint: sandboxExec(t, &got, execResponse{Artifacts: []execArtifact{
		{Name: "chart.png", Data: base64.StdEncoding.EncodeToString(png)},
		{Name: "../escape.png", Data: base64.StdEncoding.EncodeToString(png)},
	}})}
	store := newMemStore()

	res, err := newRunner(sb, &fakeExchanger{}, store).Run(context.Background(), jwt(readerJWT), "1", 5)

	if err != nil {
		t.Fatal(err)
	}
	task := sb.labels["cnp.3istor.com/task"]
	want := []Artifact{{Name: "chart.png", Mime: "image/png", URL: "/ai-artifacts/" + task + "/chart.png", Size: len(png)}}
	if fmt.Sprint(res.Artifacts) != fmt.Sprint(want) || !bytes.Equal(store.objects[task+"/chart.png"], png) || len(store.objects) != 1 {
		t.Fatalf("artifacts %+v, stored %v", res.Artifacts, store.objects)
	}
}

func TestRun_LabelsClaimWithCallingAgent(t *testing.T) {
	t.Parallel()
	var got execRequest
	sb := &fakeSandboxes{endpoint: sandboxExec(t, &got, execResponse{})}

	_, err := newRunner(sb, &fakeExchanger{}, newMemStore()).Run(context.Background(), jwt(readerJWT), "1", 5)

	if err != nil || sb.labels["cnp.3istor.com/agent"] != "agent-epitweet-grok-reader" || sb.labels["cnp.3istor.com/project"] != "epitweet" {
		t.Fatalf("labels %v, err %v", sb.labels, err)
	}
}

func TestRun_RefusesToken_WithoutProject(t *testing.T) {
	t.Parallel()
	sb := &fakeSandboxes{}

	_, err := newRunner(sb, &fakeExchanger{}, newMemStore()).Run(context.Background(), jwt(`{"azp":"x"}`), "1", 5)

	var userErr *UserError
	if !errors.As(err, &userErr) || len(sb.templates) != 0 {
		t.Fatalf("err %v, templates %v", err, sb.templates)
	}
}

type fakeRunner struct {
	jwt string
	res *Result
	err error
}

func (f *fakeRunner) Run(_ context.Context, callerJWT, _ string, _ int) (*Result, error) {
	f.jwt = callerJWT
	return f.res, f.err
}

func mcpCall(t *testing.T, h http.Handler, auth, body string) map[string]any {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/mcp", strings.NewReader(body))
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	out := map[string]any{}
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			t.Fatalf("response %q: %v", rec.Body.String(), err)
		}
	}
	out["_status"] = rec.Code
	return out
}

func TestMCP_ListsRunPythonTool(t *testing.T) {
	t.Parallel()
	h := &MCPHandler{Runner: &fakeRunner{}, Version: "test", Log: quiet}

	out := mcpCall(t, h, "", `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`)

	tools := out["result"].(map[string]any)["tools"].([]any)
	if len(tools) != 1 || tools[0].(map[string]any)["name"] != "run_python" {
		t.Fatalf("tools %v", tools)
	}
}

func TestMCP_PassesCallerToken_AndReturnsStructuredResult(t *testing.T) {
	t.Parallel()
	runner := &fakeRunner{res: &Result{Stdout: "4\n", Artifacts: []Artifact{}}}
	h := &MCPHandler{Runner: runner, Version: "test", Log: quiet}

	out := mcpCall(t, h, "Bearer agent-jwt", `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"run_python","arguments":{"code":"print(2+2)"}}}`)

	result := out["result"].(map[string]any)
	text := result["content"].([]any)[0].(map[string]any)["text"].(string)
	if runner.jwt != "agent-jwt" || result["isError"] != false || !strings.Contains(text, `"stdout":"4\n"`) {
		t.Fatalf("jwt %q, result %v", runner.jwt, result)
	}
}

func TestMCP_ReturnsToolError_WithoutCallerToken(t *testing.T) {
	t.Parallel()
	runner := &fakeRunner{}
	h := &MCPHandler{Runner: runner, Version: "test", Log: quiet}

	out := mcpCall(t, h, "", `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"run_python","arguments":{"code":"1"}}}`)

	if out["result"].(map[string]any)["isError"] != true || runner.jwt != "" {
		t.Fatalf("out %v", out)
	}
}

func TestMCP_HidesPlatformErrors_FromTheModel(t *testing.T) {
	t.Parallel()
	h := &MCPHandler{Runner: &fakeRunner{err: errors.New("dial tcp 10.0.0.1: secret detail")}, Version: "test", Log: quiet}

	out := mcpCall(t, h, "Bearer x", `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"run_python","arguments":{"code":"1"}}}`)

	text := out["result"].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if strings.Contains(text, "10.0.0.1") {
		t.Fatalf("leaked: %q", text)
	}
}

func TestMCP_AcceptsNotification_WithoutBody(t *testing.T) {
	t.Parallel()
	h := &MCPHandler{Runner: &fakeRunner{}, Version: "test", Log: quiet}

	out := mcpCall(t, h, "", `{"jsonrpc":"2.0","method":"notifications/initialized"}`)

	if out["_status"] != http.StatusAccepted {
		t.Fatalf("status %v", out["_status"])
	}
}

func TestArtifactHandler(t *testing.T) {
	t.Parallel()
	task := strings.Repeat("ab", 16)
	store := newMemStore()
	_ = store.Put(context.Background(), task+"/chart.png", "image/png", []byte("png"))
	_ = store.Put(context.Background(), task+"/page.html", "text/html", []byte("<script>"))
	now := time.Now()
	tests := []struct {
		name, path, wantType, wantDisposition string
		at                                    time.Time
		wantStatus                            int
	}{
		{name: "serves png inline", path: task + "/chart.png", at: now, wantStatus: 200, wantType: "image/png", wantDisposition: "inline"},
		{name: "html is only a download", path: task + "/page.html", at: now, wantStatus: 200, wantType: "application/octet-stream", wantDisposition: "attachment"},
		{name: "unknown artifact", path: task + "/nope.png", at: now, wantStatus: 404},
		{name: "bad task id", path: "../../etc/chart.png", at: now, wantStatus: 404},
		{name: "expired after 24 h", path: task + "/chart.png", at: now.Add(25 * time.Hour), wantStatus: 410},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h := &ArtifactHandler{Store: store, Log: quiet, Now: func() time.Time { return tt.at }}
			rec := httptest.NewRecorder()

			h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, ArtifactRoute+tt.path, nil))

			if rec.Code != tt.wantStatus || rec.Header().Get("Content-Type") != tt.wantType && tt.wantType != "" ||
				!strings.HasPrefix(rec.Header().Get("Content-Disposition"), tt.wantDisposition) {
				t.Fatalf("status %d, type %q, disposition %q", rec.Code, rec.Header().Get("Content-Type"), rec.Header().Get("Content-Disposition"))
			}
		})
	}
}
