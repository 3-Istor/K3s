// Package gwproxy is the agent-side half of the AI gateway auth: kagent only
// knows static API keys, so the agent talks to this proxy on 127.0.0.1 and the
// proxy forwards to the gateway with the agent's own short-lived JWT.
package gwproxy

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
)

// KagentHostHeader carries the original host of a sub-agent call when kagent's
// proxy.url points at this proxy.
const KagentHostHeader = "X-Kagent-Host"

// HealthPath answers 200 when the proxy can obtain a token.
const HealthPath = "/_gw/healthz"

const maxCardBytes = 1 << 20

// TokenSource returns a bearer token valid for the next request.
type TokenSource interface {
	Token(ctx context.Context) (string, error)
}

type requestKey struct{}

type requestInfo struct {
	token     string
	localHost string
}

// New returns the proxy handler.
func New(upstream *url.URL, tokens TokenSource, log *slog.Logger) http.Handler {
	rp := &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.SetURL(upstream)
			pr.Out.Host = upstream.Host
			for _, h := range []string{"Authorization", "X-Api-Key", "Proxy-Authorization", KagentHostHeader} {
				pr.Out.Header.Del(h)
			}
			pr.Out.Header.Set("Authorization", "Bearer "+pr.In.Context().Value(requestKey{}).(requestInfo).token)
			if isAgentCardPath(pr.Out.URL.Path) {
				pr.Out.Header.Set("Accept-Encoding", "identity")
			}
		},
		FlushInterval:  -1,
		ModifyResponse: rewriteAgentCard,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			log.Error("upstream request failed", "path", r.URL.Path, "err", err)
			writeError(w, http.StatusBadGateway, "gateway_unreachable", "The AI gateway could not be reached.")
		},
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == HealthPath {
			if _, err := tokens.Token(r.Context()); err != nil {
				writeError(w, http.StatusServiceUnavailable, "token_unavailable", err.Error())
				return
			}
			w.WriteHeader(http.StatusOK)
			return
		}
		if host := r.Header.Get(KagentHostHeader); host != "" && !strings.HasPrefix(r.URL.Path, "/a2a/") {
			prefix, err := a2aPrefix(host)
			if err != nil {
				writeError(w, http.StatusBadRequest, "bad_agent_host", err.Error())
				return
			}
			r.URL.Path = prefix + r.URL.Path
			r.URL.RawPath = ""
		}
		tok, err := tokens.Token(r.Context())
		if err != nil {
			log.Error("no token for the gateway", "err", err)
			writeError(w, http.StatusServiceUnavailable, "token_unavailable", "The agent could not obtain its gateway token.")
			return
		}
		info := requestInfo{token: tok, localHost: r.Host}
		rp.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestKey{}, info)))
	})
}

// a2aPrefix maps kagent's sub-agent host "<agent>.<project>-<agent>" to the
// gateway route "/a2a/<project>/<agent>". Agent namespaces are always named
// <project>-<agent>, so anything else is not a platform agent.
func a2aPrefix(host string) (string, error) {
	agent, namespace, ok := strings.Cut(host, ".")
	if !ok || agent == "" {
		return "", fmt.Errorf("agent host %q is not <agent>.<namespace>", host)
	}
	namespace, _, _ = strings.Cut(namespace, ".")
	project, found := strings.CutSuffix(namespace, "-"+agent)
	if !found || project == "" {
		return "", fmt.Errorf("namespace %q of agent %q is not <project>-%s", namespace, agent, agent)
	}
	return "/a2a/" + project + "/" + agent, nil
}

func isAgentCardPath(path string) bool {
	return strings.HasPrefix(path, "/a2a/") &&
		(strings.HasSuffix(path, "/.well-known/agent-card.json") || strings.HasSuffix(path, "/.well-known/agent.json"))
}

// rewriteAgentCard points every interface URL of an agent card at this proxy:
// the A2A client sends its messages to the card's URL, which kagent sets to the
// agent's pod Service, a path the network policy blocks.
func rewriteAgentCard(resp *http.Response) error {
	req := resp.Request
	if resp.StatusCode != http.StatusOK || !isAgentCardPath(req.URL.Path) {
		return nil
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxCardBytes+1))
	resp.Body.Close()
	if err != nil {
		return err
	}
	if len(body) > maxCardBytes {
		return errors.New("agent card larger than 1 MiB")
	}
	route := req.URL.Path[:strings.Index(req.URL.Path, "/.well-known/")]
	base := "http://" + req.Context().Value(requestKey{}).(requestInfo).localHost + route
	var card any
	if err := json.Unmarshal(body, &card); err != nil {
		return fmt.Errorf("agent card: %w", err)
	}
	rewriteURLs(card, base)
	out, err := json.Marshal(card)
	if err != nil {
		return err
	}
	resp.Body = io.NopCloser(bytes.NewReader(out))
	resp.ContentLength = int64(len(out))
	resp.Header.Set("Content-Length", strconv.Itoa(len(out)))
	resp.Header.Del("Content-Encoding")
	return nil
}

func rewriteURLs(node any, base string) {
	switch v := node.(type) {
	case map[string]any:
		for k, child := range v {
			if s, ok := child.(string); ok && k == "url" && strings.HasPrefix(s, "http") {
				v[k] = base
				continue
			}
			rewriteURLs(child, base)
		}
	case []any:
		for _, child := range v {
			rewriteURLs(child, base)
		}
	}
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": code, "message": message})
}
