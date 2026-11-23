// web-search is the platform MCP server of the web_search tool.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/3-Istor/K3s/images/ai-runtime/internal/websearch"
)

var version = "dev"

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if err := run(log); err != nil {
		log.Error("web-search stopped", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	maxTokens, err := strconv.Atoi(envOr("MAX_TOKENS", "1500"))
	if err != nil || maxTokens < 1 || maxTokens > 1500 {
		return errors.New("MAX_TOKENS must be an integer between 1 and 1500")
	}
	searcher := &websearch.Searcher{
		HTTP:       &http.Client{Timeout: 90 * time.Second},
		GatewayURL: envOr("GATEWAY_URL", "http://ai-gateway.ai-gateway.svc.cluster.local:8080"),
		Model:      envOr("MODEL", "claude-haiku-5-5"),
		Effort:     envOr("EFFORT", "low"),
		MaxTokens:  maxTokens,
		ToolType:   envOr("SEARCH_TOOL_TYPE", "web_search_20260209"),
		Now:        time.Now,
	}

	mux := http.NewServeMux()
	mux.Handle("/mcp", &websearch.MCPHandler{Searcher: searcher, Version: version, Log: log})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	listen := envOr("LISTEN", ":3000")
	srv := &http.Server{Addr: listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	errc := make(chan error, 1)
	go func() { errc <- srv.ListenAndServe() }()
	log.Info("web-search listening", "addr", listen, "version", version, "model", searcher.Model, "tool", searcher.ToolType)
	select {
	case err := <-errc:
		return fmt.Errorf("listen: %w", err)
	case <-ctx.Done():
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
