package gwproxy

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

type staticTokens struct {
	token string
	err   error
}

func (s staticTokens) Token(context.Context) (string, error) { return s.token, s.err }

type seen struct {
	path, auth, apiKey, kagentHost string
}

func newUpstream(t *testing.T, got *seen, handler http.HandlerFunc) *url.URL {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*got = seen{path: r.URL.Path, auth: r.Header.Get("Authorization"), apiKey: r.Header.Get("X-Api-Key"), kagentHost: r.Header.Get(KagentHostHeader)}
		if handler != nil {
			handler(w, r)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	return u
}

func newProxy(t *testing.T, upstream *url.URL, tokens TokenSource) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(New(upstream, tokens, slog.New(slog.NewTextHandler(io.Discard, nil))))
	t.Cleanup(srv.Close)
	return srv
}

func TestProxy_ReplacesAgentCredentials_WithGatewayToken(t *testing.T) {
	t.Parallel()
	var got seen
	proxy := newProxy(t, newUpstream(t, &got, nil), staticTokens{token: "jwt-1"})
	req, _ := http.NewRequest(http.MethodPost, proxy.URL+"/v1/messages", strings.NewReader(`{}`))
	req.Header.Set("X-Api-Key", "placeholder-gateway-holds-the-key")
	req.Header.Set("Authorization", "Bearer forged")

	resp, err := http.DefaultClient.Do(req)

	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got != (seen{path: "/v1/messages", auth: "Bearer jwt-1"}) {
		t.Fatalf("upstream saw %+v", got)
	}
}

func TestProxy_RoutesSubAgentCall_ToGatewayA2ARoute(t *testing.T) {
	t.Parallel()
	var got seen
	proxy := newProxy(t, newUpstream(t, &got, nil), staticTokens{token: "jwt"})
	req, _ := http.NewRequest(http.MethodPost, proxy.URL+"/", strings.NewReader(`{}`))
	req.Header.Set(KagentHostHeader, "grok-actor.epitweet-grok-actor")

	resp, err := http.DefaultClient.Do(req)

	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got.path != "/a2a/epitweet/grok-actor/" || got.kagentHost != "" {
		t.Fatalf("upstream saw %+v", got)
	}
}

func TestProxy_RefusesSubAgent_OutsideItsProjectNamespace(t *testing.T) {
	t.Parallel()
	var got seen
	proxy := newProxy(t, newUpstream(t, &got, nil), staticTokens{token: "jwt"})
	req, _ := http.NewRequest(http.MethodPost, proxy.URL+"/", nil)
	req.Header.Set(KagentHostHeader, "reader.kube-system")

	resp, err := http.DefaultClient.Do(req)

	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest || got.path != "" {
		t.Fatalf("status %d, upstream saw %+v", resp.StatusCode, got)
	}
}

func TestProxy_RewritesAgentCardURLs_ToItself(t *testing.T) {
	t.Parallel()
	var got seen
	card := `{"name":"reader","url":"http://reader.demo-reader:8080","supportedInterfaces":[{"url":"http://reader.demo-reader:8080","protocolBinding":"JSONRPC"}],"iconUrl":"https://x/icon.png"}`
	upstream := newUpstream(t, &got, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, card)
	})
	proxy := newProxy(t, upstream, staticTokens{token: "jwt"})
	req, _ := http.NewRequest(http.MethodGet, proxy.URL+"/.well-known/agent-card.json", nil)
	req.Header.Set(KagentHostHeader, "reader.demo-reader")

	resp, err := http.DefaultClient.Do(req)

	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var out struct {
		URL        string `json:"url"`
		IconURL    string `json:"iconUrl"`
		Interfaces []struct {
			URL string `json:"url"`
		} `json:"supportedInterfaces"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		t.Fatal(err)
	}
	want := proxy.URL + "/a2a/demo/reader"
	if out.URL != want || out.Interfaces[0].URL != want || out.IconURL != "https://x/icon.png" {
		t.Fatalf("card after rewrite: %+v, want url %s", out, want)
	}
}

func TestProxy_KeepsA2APath_WhenClientFollowsRewrittenCard(t *testing.T) {
	t.Parallel()
	var got seen
	proxy := newProxy(t, newUpstream(t, &got, nil), staticTokens{token: "jwt"})
	req, _ := http.NewRequest(http.MethodPost, proxy.URL+"/a2a/demo/reader", strings.NewReader(`{}`))
	req.Header.Set(KagentHostHeader, "reader.demo-reader")

	resp, err := http.DefaultClient.Do(req)

	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if got.path != "/a2a/demo/reader" {
		t.Fatalf("upstream saw %+v", got)
	}
}

func TestProxy_Returns503_WhenNoTokenCanBeObtained(t *testing.T) {
	t.Parallel()
	var got seen
	proxy := newProxy(t, newUpstream(t, &got, nil), staticTokens{err: errors.New("keycloak down")})

	resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{}`))

	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusServiceUnavailable || got.path != "" {
		t.Fatalf("status %d, upstream saw %+v", resp.StatusCode, got)
	}
}

func TestProxy_StreamsResponse_BeforeUpstreamFinishes(t *testing.T) {
	t.Parallel()
	var got seen
	release := make(chan struct{})
	upstream := newUpstream(t, &got, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = io.WriteString(w, "event: message_start\n\n")
		w.(http.Flusher).Flush()
		<-release
	})
	proxy := newProxy(t, upstream, staticTokens{token: "jwt"})

	resp, err := http.Post(proxy.URL+"/v1/messages", "application/json", strings.NewReader(`{"stream":true}`))

	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	buf := make([]byte, len("event: message_start"))
	_, err = io.ReadFull(resp.Body, buf)
	close(release)
	if err != nil || string(buf) != "event: message_start" {
		t.Fatalf("first event not streamed: %q, %v", buf, err)
	}
}

func TestA2APrefix(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, host, want string
		wantErr          bool
	}{
		{name: "agent namespace", host: "grok-reader.epitweet-grok-reader", want: "/a2a/epitweet/grok-reader"},
		{name: "fully qualified", host: "a.p-a.svc.cluster.local", want: "/a2a/p/a"},
		{name: "project with dashes", host: "bot.my-proj-bot", want: "/a2a/my-proj/bot"},
		{name: "foreign namespace", host: "a.kagent", wantErr: true},
		{name: "no project", host: "a.-a", wantErr: true},
		{name: "no namespace", host: "a", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := a2aPrefix(tt.host)
			if (err != nil) != tt.wantErr || got != tt.want {
				t.Fatalf("a2aPrefix(%q) = %q, %v", tt.host, got, err)
			}
		})
	}
}
