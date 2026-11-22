package runpython

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const saDir = "/var/run/secrets/kubernetes.io/serviceaccount"

// KubeSandboxes claims sandboxes from agent-sandbox warm pools through the API server.
type KubeSandboxes struct {
	APIServer string
	Namespace string
	HTTP      *http.Client
	// TokenFile is re-read on each call: the projected token rotates.
	TokenFile string
	// ReadyTimeout bounds the wait for a sandbox (a cold Kata VM takes longest).
	ReadyTimeout time.Duration
	PollInterval time.Duration
	Now          func() time.Time
}

// NewInClusterSandboxes uses the pod's service account.
func NewInClusterSandboxes(namespace string) (*KubeSandboxes, error) {
	ca, err := os.ReadFile(saDir + "/ca.crt")
	if err != nil {
		return nil, err
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(ca) {
		return nil, errors.New("service account CA is not PEM")
	}
	host, port := os.Getenv("KUBERNETES_SERVICE_HOST"), os.Getenv("KUBERNETES_SERVICE_PORT")
	if host == "" || port == "" {
		return nil, errors.New("not running in a cluster")
	}
	return &KubeSandboxes{
		APIServer:    "https://" + host + ":" + port,
		Namespace:    namespace,
		HTTP:         &http.Client{Timeout: 30 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}}},
		TokenFile:    saDir + "/token",
		ReadyTimeout: 120 * time.Second,
		PollInterval: 300 * time.Millisecond,
		Now:          time.Now,
	}, nil
}

type apiStatusError struct {
	code int
	body string
}

func (e *apiStatusError) Error() string { return fmt.Sprintf("kube API %d: %s", e.code, e.body) }

func (k *KubeSandboxes) do(ctx context.Context, method, path string, body any, out any) error {
	var rdr io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return err
		}
		rdr = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, k.APIServer+path, rdr)
	if err != nil {
		return err
	}
	token, err := os.ReadFile(k.TokenFile)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+string(bytes.TrimSpace(token)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := k.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		return &apiStatusError{code: resp.StatusCode, body: string(data)}
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}

type condition struct {
	Type   string `json:"type"`
	Status string `json:"status"`
}

// Acquire creates SandboxClaim name on the template's warm pool and waits until its sandbox is Ready.
func (k *KubeSandboxes) Acquire(ctx context.Context, template, name string, labels map[string]string) (string, string, error) {
	claim := map[string]any{
		"apiVersion": "extensions.agents.x-k8s.io/v1beta1",
		"kind":       "SandboxClaim",
		"metadata":   map[string]any{"name": name, "namespace": k.Namespace, "labels": labels},
		"spec": map[string]any{
			"warmPoolRef": map[string]any{"name": template},
			// Safety net if run-python dies mid-run: the controller deletes it.
			"lifecycle": map[string]any{"shutdownPolicy": "Delete", "shutdownTime": k.Now().Add(10 * time.Minute).UTC().Format(time.RFC3339)},
		},
	}
	base := "/apis/extensions.agents.x-k8s.io/v1beta1/namespaces/" + k.Namespace + "/sandboxclaims"
	if err := k.do(ctx, http.MethodPost, base, claim, nil); err != nil {
		return "", "", fmt.Errorf("create SandboxClaim: %w", err)
	}

	deadline := k.Now().Add(k.ReadyTimeout)
	for {
		endpoint, err := k.readyEndpoint(ctx, base+"/"+name)
		if err != nil {
			return name, "", err
		}
		if endpoint != "" {
			return name, endpoint, nil
		}
		if k.Now().After(deadline) {
			return name, "", fmt.Errorf("sandbox of claim %s not ready after %s", name, k.ReadyTimeout)
		}
		select {
		case <-ctx.Done():
			return name, "", ctx.Err()
		case <-time.After(k.PollInterval):
		}
	}
}

func (k *KubeSandboxes) readyEndpoint(ctx context.Context, claimPath string) (string, error) {
	var claim struct {
		Status struct {
			Sandbox struct {
				Name string `json:"name"`
			} `json:"sandbox"`
		} `json:"status"`
	}
	if err := k.do(ctx, http.MethodGet, claimPath, nil, &claim); err != nil {
		return "", fmt.Errorf("read SandboxClaim: %w", err)
	}
	if claim.Status.Sandbox.Name == "" {
		return "", nil
	}
	var sb struct {
		Status struct {
			ServiceFQDN string      `json:"serviceFQDN"`
			Conditions  []condition `json:"conditions"`
		} `json:"status"`
	}
	path := "/apis/agents.x-k8s.io/v1beta1/namespaces/" + k.Namespace + "/sandboxes/" + claim.Status.Sandbox.Name
	if err := k.do(ctx, http.MethodGet, path, nil, &sb); err != nil {
		var se *apiStatusError
		if errors.As(err, &se) && se.code == http.StatusNotFound {
			return "", nil
		}
		return "", fmt.Errorf("read Sandbox: %w", err)
	}
	for _, c := range sb.Status.Conditions {
		if c.Type == "Ready" && c.Status == "True" && sb.Status.ServiceFQDN != "" {
			return "http://" + sb.Status.ServiceFQDN + ":8888", nil
		}
	}
	return "", nil
}

// Release deletes the claim; its sandbox goes with it.
func (k *KubeSandboxes) Release(ctx context.Context, claim string) error {
	err := k.do(ctx, http.MethodDelete, "/apis/extensions.agents.x-k8s.io/v1beta1/namespaces/"+k.Namespace+"/sandboxclaims/"+claim, nil, nil)
	var se *apiStatusError
	if errors.As(err, &se) && se.code == http.StatusNotFound {
		return nil
	}
	return err
}

// NamespaceLabel returns one label of a namespace, "" when absent or the namespace does not exist.
func (k *KubeSandboxes) NamespaceLabel(ctx context.Context, namespace, label string) (string, error) {
	var ns struct {
		Metadata struct {
			Labels map[string]string `json:"labels"`
		} `json:"metadata"`
	}
	err := k.do(ctx, http.MethodGet, "/api/v1/namespaces/"+namespace, nil, &ns)
	var se *apiStatusError
	if errors.As(err, &se) && se.code == http.StatusNotFound {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return ns.Metadata.Labels[label], nil
}
