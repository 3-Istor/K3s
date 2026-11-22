package runpython

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"path"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ArtifactRoute is the gateway route prefix of artifacts, kept as is up to this server.
const ArtifactRoute = "/ai-artifacts/"

// ArtifactTTL is how long an artifact URL answers; the bucket lifecycle deletes later.
const ArtifactTTL = 24 * time.Hour

var taskID = regexp.MustCompile(`^[0-9a-f]{32}$`)

// Only these are shown inline; anything else is a download, so a file the
// model wrote can never run as a page on the gateway's origin.
var inlineTypes = map[string]string{
	".png":  "image/png",
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".gif":  "image/gif",
	".webp": "image/webp",
	".csv":  "text/csv; charset=utf-8",
	".txt":  "text/plain; charset=utf-8",
	".json": "application/json",
}

// ErrNotFound is returned by ObjectReader for a missing key.
var ErrNotFound = errors.New("artifact not found")

// Object is an artifact read back from the store.
type Object struct {
	Body         io.ReadCloser
	Size         int64
	LastModified time.Time
}

// ObjectReader reads artifacts back.
type ObjectReader interface {
	Get(ctx context.Context, key string) (*Object, error)
}

// ArtifactHandler serves GET /ai-artifacts/<task>/<name>.
type ArtifactHandler struct {
	Store ObjectReader
	Log   *slog.Logger
	Now   func() time.Time
}

func (h *ArtifactHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	task, name, ok := strings.Cut(strings.TrimPrefix(r.URL.Path, ArtifactRoute), "/")
	if !ok || !taskID.MatchString(task) || !artifactName.MatchString(name) {
		http.NotFound(w, r)
		return
	}
	obj, err := h.Store.Get(r.Context(), task+"/"+name)
	if errors.Is(err, ErrNotFound) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		h.Log.Error("artifact read failed", "task", task, "name", name, "err", err)
		http.Error(w, "artifact store unavailable", http.StatusBadGateway)
		return
	}
	defer obj.Body.Close()
	if h.Now().Sub(obj.LastModified) > ArtifactTTL {
		http.Error(w, "artifact expired", http.StatusGone)
		return
	}
	ct, inline := inlineTypes[strings.ToLower(path.Ext(name))]
	if !inline {
		ct = "application/octet-stream"
	}
	disposition := "inline"
	if !inline {
		disposition = "attachment"
	}
	hdr := w.Header()
	hdr.Set("Content-Type", ct)
	hdr.Set("Content-Length", strconv.FormatInt(obj.Size, 10))
	hdr.Set("Content-Disposition", disposition+`; filename="`+name+`"`)
	hdr.Set("X-Content-Type-Options", "nosniff")
	hdr.Set("Content-Security-Policy", "default-src 'none'; sandbox")
	hdr.Set("Cache-Control", "private, max-age=3600")
	if r.Method == http.MethodHead {
		return
	}
	if _, err := io.Copy(w, obj.Body); err != nil {
		h.Log.Warn("artifact copy interrupted", "task", task, "name", name, "err", err)
	}
}
