package runpython

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeAPI answers like the API server with agent-sandbox: the claim gets its
// sandbox after a few reads, the sandbox turns Ready after a few more.
type fakeAPI struct {
	mu      sync.Mutex
	reads   int
	created map[string]any
	deleted []string
}

func (f *fakeAPI) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if r.Header.Get("Authorization") != "Bearer sa-token" {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	switch {
	case r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, "/sandboxclaims"):
		_ = json.NewDecoder(r.Body).Decode(&f.created)
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{}`))
	case r.Method == http.MethodGet && strings.Contains(r.URL.Path, "/sandboxclaims/"):
		f.reads++
		if f.reads < 2 {
			_, _ = w.Write([]byte(`{"status":{}}`))
			return
		}
		_, _ = w.Write([]byte(`{"status":{"sandbox":{"name":"python-abc"}}}`))
	case r.Method == http.MethodGet && strings.HasSuffix(r.URL.Path, "/sandboxes/python-abc"):
		ready := "False"
		if f.reads >= 3 {
			ready = "True"
		}
		_, _ = w.Write([]byte(`{"status":{"serviceFQDN":"python-abc.ai-sandbox.svc.cluster.local","conditions":[{"type":"Ready","status":"` + ready + `"}]}}`))
	case r.Method == http.MethodDelete:
		f.deleted = append(f.deleted, r.URL.Path)
		_, _ = w.Write([]byte(`{}`))
	case r.Method == http.MethodGet && r.URL.Path == "/api/v1/namespaces/p-a":
		_, _ = w.Write([]byte(`{"metadata":{"labels":{"cnp.3istor.com/isolation":"kata"}}}`))
	default:
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"kind":"Status","code":404}`))
	}
}

func newKube(t *testing.T, api http.Handler) *KubeSandboxes {
	t.Helper()
	srv := httptest.NewServer(api)
	t.Cleanup(srv.Close)
	tokenFile := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(tokenFile, []byte("sa-token\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return &KubeSandboxes{APIServer: srv.URL, Namespace: "ai-sandbox", HTTP: srv.Client(), TokenFile: tokenFile,
		ReadyTimeout: 5 * time.Second, PollInterval: time.Millisecond, Now: time.Now}
}

func TestKubeSandboxes_WaitsForReadySandbox_OnTheTemplatePool(t *testing.T) {
	t.Parallel()
	api := &fakeAPI{}
	k := newKube(t, api)
	claim, endpoint, err := k.Acquire(context.Background(), "python", "run-ffffffffffffffffffff", map[string]string{"cnp.3istor.com/project": "p"})

	if err != nil {
		t.Fatal(err)
	}
	spec := api.created["spec"].(map[string]any)
	if claim != "run-ffffffffffffffffffff" || endpoint != "http://python-abc.ai-sandbox.svc.cluster.local:8888" ||
		spec["warmPoolRef"].(map[string]any)["name"] != "python" || spec["lifecycle"].(map[string]any)["shutdownPolicy"] != "Delete" {
		t.Fatalf("claim %q endpoint %q created %v", claim, endpoint, api.created)
	}
}

func TestKubeSandboxes_ReleaseDeletesClaim_AndIgnoresMissingOne(t *testing.T) {
	t.Parallel()
	api := &fakeAPI{}
	k := newKube(t, api)

	err := k.Release(context.Background(), "run-1")

	if err != nil || len(api.deleted) != 1 || !strings.HasSuffix(api.deleted[0], "/sandboxclaims/run-1") {
		t.Fatalf("err %v deleted %v", err, api.deleted)
	}
}

func TestKubeSandboxes_NamespaceLabel(t *testing.T) {
	t.Parallel()
	k := newKube(t, &fakeAPI{})

	kata, err1 := k.NamespaceLabel(context.Background(), "p-a", IsolationLabel)
	missing, err2 := k.NamespaceLabel(context.Background(), "gone", IsolationLabel)

	if kata != "kata" || missing != "" || err1 != nil || err2 != nil {
		t.Fatalf("got %q %q, errs %v %v", kata, missing, err1, err2)
	}
}
