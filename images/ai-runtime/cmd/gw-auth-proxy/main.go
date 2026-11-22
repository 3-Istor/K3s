// gw-auth-proxy runs next to a kagent agent and forwards its model, MCP and
// A2A calls to the AI gateway with the agent's Keycloak client_credentials JWT.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/gwproxy"
	"github.com/3-Istor/K3s/images/ai-runtime/internal/oidc"
)

const (
	defaultListen   = "127.0.0.1:15001"
	defaultUpstream = "http://ai-gateway.ai-gateway.svc.cluster.local:8080"
	defaultTokenURL = "http://keycloakx-http.keycloak.svc.cluster.local/realms/3istor/protocol/openid-connect/token"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	listen := envOr("GW_LISTEN", defaultListen)
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(healthcheck(listen))
	}
	if err := run(log, listen); err != nil {
		log.Error("gw-auth-proxy stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger, listen string) error {
	upstream, err := url.Parse(envOr("GW_UPSTREAM", defaultUpstream))
	if err != nil || upstream.Scheme == "" || upstream.Host == "" {
		return fmt.Errorf("GW_UPSTREAM must be an absolute URL")
	}
	clientID, secret := os.Getenv("GW_CLIENT_ID"), os.Getenv("GW_CLIENT_SECRET")
	if clientID == "" || secret == "" {
		return errors.New("GW_CLIENT_ID and GW_CLIENT_SECRET are required")
	}
	tokens := &oidc.CachedSource{
		Client:        &oidc.Client{TokenURL: envOr("GW_TOKEN_URL", defaultTokenURL), ClientID: clientID, ClientSecret: secret},
		RefreshBefore: 60 * time.Second,
	}

	srv := &http.Server{
		Addr:              listen,
		Handler:           gwproxy.New(upstream, tokens, log),
		ReadHeaderTimeout: 10 * time.Second,
	}
	ln, err := net.Listen("tcp", listen)
	if err != nil {
		return err
	}
	log.Info("gw-auth-proxy listening", "addr", listen, "upstream", upstream.String(), "client_id", clientID)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	errc := make(chan error, 1)
	go func() { errc <- srv.Serve(ln) }()
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	// The agent container gets SIGTERM at the same time: let its in-flight
	// model calls finish rather than cut them.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

func healthcheck(listen string) int {
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("http://" + listen + gwproxy.HealthPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, "health:", resp.Status)
		return 1
	}
	return 0
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
