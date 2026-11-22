// run-python is the platform MCP server of the run_python tool (code mode).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/oidc"
	"github.com/3-Istor/K3s/images/ai-runtime/internal/runpython"
)

var version = "dev"

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if err := run(log); err != nil {
		log.Error("run-python stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	store, err := runpython.NewS3Store(cfg.s3Endpoint, false, cfg.bucket, cfg.s3Key, cfg.s3Secret)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	expiryCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	if err := store.EnsureExpiry(expiryCtx, 1); err != nil {
		// Serving still works; the TTL check in the handler keeps URLs at 24 h.
		log.Warn("bucket lifecycle not set", "bucket", cfg.bucket, "err", err)
	}
	cancel()
	sandboxes, err := runpython.NewInClusterSandboxes(cfg.sandboxNamespace)
	if err != nil {
		return err
	}

	runner := &runpython.Runner{
		Sandboxes:  sandboxes,
		Exchanger:  &oidc.Client{TokenURL: cfg.tokenURL, ClientID: cfg.runnerID, ClientSecret: cfg.runnerSecret},
		Store:      store,
		HTTP:       &http.Client{},
		GatewayURL: cfg.gatewayURL,
		Templates:  map[string]string{"gvisor": cfg.templateGvisor, "kata": cfg.templateKata},
		Log:        log,
		Now:        time.Now,
	}
	mux := http.NewServeMux()
	mux.Handle("/mcp", &runpython.MCPHandler{Runner: runner, Version: version, Log: log})
	mux.Handle(runpython.ArtifactRoute, &runpython.ArtifactHandler{Store: store, Log: log, Now: time.Now})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	srv := &http.Server{Addr: cfg.listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	errc := make(chan error, 1)
	go func() { errc <- srv.ListenAndServe() }()
	log.Info("run-python listening", "addr", cfg.listen, "version", version, "sandbox_namespace", cfg.sandboxNamespace)
	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancelShutdown()
	return srv.Shutdown(shutdownCtx)
}

type config struct {
	listen, sandboxNamespace, templateGvisor, templateKata string
	tokenURL, runnerID, runnerSecret, gatewayURL           string
	s3Endpoint, bucket, s3Key, s3Secret                    string
}

func loadConfig() (config, error) {
	c := config{
		listen:           envOr("LISTEN", ":3000"),
		sandboxNamespace: envOr("SANDBOX_NAMESPACE", "ai-sandbox"),
		templateGvisor:   envOr("SANDBOX_TEMPLATE_GVISOR", "python"),
		templateKata:     envOr("SANDBOX_TEMPLATE_KATA", "python-kata"),
		tokenURL:         envOr("TOKEN_URL", "http://keycloakx-http.keycloak.svc.cluster.local/realms/3istor/protocol/openid-connect/token"),
		runnerID:         envOr("RUNNER_CLIENT_ID", "sandbox-runner"),
		runnerSecret:     os.Getenv("RUNNER_CLIENT_SECRET"),
		gatewayURL:       envOr("GATEWAY_URL", "http://ai-gateway.ai-gateway.svc.cluster.local:8080"),
		// BUCKET_* come from the ObjectBucketClaim ConfigMap, AWS_* from its Secret.
		bucket:   os.Getenv("BUCKET_NAME"),
		s3Key:    os.Getenv("AWS_ACCESS_KEY_ID"),
		s3Secret: os.Getenv("AWS_SECRET_ACCESS_KEY"),
	}
	if host, port := os.Getenv("BUCKET_HOST"), os.Getenv("BUCKET_PORT"); host != "" && port != "" {
		c.s3Endpoint = host + ":" + port
	}
	var missing []string
	for name, v := range map[string]string{"RUNNER_CLIENT_SECRET": c.runnerSecret, "BUCKET_NAME": c.bucket, "BUCKET_HOST/BUCKET_PORT": c.s3Endpoint,
		"AWS_ACCESS_KEY_ID": c.s3Key, "AWS_SECRET_ACCESS_KEY": c.s3Secret} {
		if v == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return c, errors.New(fmt.Sprint("missing configuration: ", missing))
	}
	return c, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
