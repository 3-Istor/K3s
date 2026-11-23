package websearch

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

// Shape of a real claude-haiku-5-5 answer with web_search_20260209 (trial evidence).
const searchResponse = `{"stop_reason":"end_turn","content":[
 {"type":"thinking","thinking":"","signature":"x"},
 {"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{"query":"Kubernetes 1.34 release date"}},
 {"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[
   {"type":"web_search_result","title":"Kubernetes v1.34 release","url":"https://kubernetes.io/blog/v1-34","encrypted_content":"e","page_age":"90 days ago"},
   {"type":"web_search_result","title":"Kubernetes 1.34 deep dive","url":"https://palark.com/k134","encrypted_content":"e"},
   {"type":"web_search_result","title":"Third","url":"https://example.org/3","encrypted_content":"e"}]},
 {"type":"text","text":"[{\"url\":\"https://palark.com/k134\",\"snippet\":\"Released on 27 August 2025.\"},{\"url\":\"https://invented.example/fake\",\"snippet\":\"made up\"}]"}],
 "usage":{"input_tokens":19000,"output_tokens":400,"server_tool_use":{"web_search_requests":1}}}`

type gateway struct {
	status  int
	headers map[string]string
	body    string
	auth    string
	request map[string]any
}

func (g *gateway) start(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			http.NotFound(w, r)
			return
		}
		g.auth = r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&g.request)
		for k, v := range g.headers {
			w.Header().Set(k, v)
		}
		w.WriteHeader(g.status)
		_, _ = io.WriteString(w, g.body)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func newSearcher(url string) *Searcher {
	return &Searcher{
		HTTP: http.DefaultClient, GatewayURL: url, Model: "claude-haiku-5-5", Effort: "low",
		MaxTokens: 1500, ToolType: "web_search_20260209",
		Now: func() time.Time { return time.Date(2026, 11, 23, 12, 0, 0, 0, time.UTC) },
	}
}

func TestSearch_CallsGatewayAsTheAgent_WithOneCheapSearch(t *testing.T) {
	t.Parallel()
	g := &gateway{status: 200, body: searchResponse}
	srv := g.start(t)

	_, err := newSearcher(srv.URL).Search(context.Background(), "agent-jwt", "k8s 1.34", 3)

	if err != nil {
		t.Fatal(err)
	}
	tool := g.request["tools"].([]any)[0].(map[string]any)
	if g.auth != "Bearer agent-jwt" || g.request["model"] != "claude-haiku-5-5" || g.request["max_tokens"] != 1500.0 ||
		tool["type"] != "web_search_20260209" || tool["max_uses"] != 1.0 ||
		g.request["output_config"].(map[string]any)["effort"] != "low" {
		t.Fatalf("auth %q request %v", g.auth, g.request)
	}
}

func TestSearch_ReturnsOnlyURLsTheSearchFound_CondensedFirst(t *testing.T) {
	t.Parallel()
	srv := (&gateway{status: 200, body: searchResponse}).start(t)

	res, err := newSearcher(srv.URL).Search(context.Background(), "jwt", "k8s 1.34", 2)

	if err != nil {
		t.Fatal(err)
	}
	want := []Source{
		{Title: "Kubernetes 1.34 deep dive", URL: "https://palark.com/k134", Snippet: "Released on 27 August 2025."},
		{Title: "Kubernetes v1.34 release", URL: "https://kubernetes.io/blog/v1-34"},
	}
	got, _ := json.Marshal(res)
	exp, _ := json.Marshal(&Result{Results: want, SearchedAt: "2026-11-23T12:00:00Z"})
	if string(got) != string(exp) {
		t.Fatalf("got  %s\nwant %s", got, exp)
	}
}

func TestSearch_FallsBackToSearchResults_WhenModelTextIsNotJSON(t *testing.T) {
	t.Parallel()
	body := strings.Replace(searchResponse,
		`"text":"[{\"url\":\"https://palark.com/k134\",\"snippet\":\"Released on 27 August 2025.\"},{\"url\":\"https://invented.example/fake\",\"snippet\":\"made up\"}]"`,
		`"text":"Kubernetes 1.34 shipped in August.","citations":[{"type":"web_search_result_location","url":"https://example.org/3","cited_text":"v1.34 is out"}]`, 1)
	srv := (&gateway{status: 200, body: body}).start(t)

	res, err := newSearcher(srv.URL).Search(context.Background(), "jwt", "k8s 1.34", 5)

	if err != nil || len(res.Results) != 3 || res.Results[2].Snippet != "v1.34 is out" {
		t.Fatalf("res %+v err %v", res, err)
	}
}

func TestSearch_ReportsBudgetRefusal_ToTheAgent(t *testing.T) {
	t.Parallel()
	srv := (&gateway{status: 429, headers: map[string]string{"x-cnp-refusal": "budget"}}).start(t)

	_, err := newSearcher(srv.URL).Search(context.Background(), "jwt", "q", 5)

	if err == nil || !strings.Contains(err.Error(), "budget") {
		t.Fatalf("err %v", err)
	}
}

func TestSearch_Fails_WhenSearchEngineReturnsAnError(t *testing.T) {
	t.Parallel()
	body := `{"stop_reason":"end_turn","content":[{"type":"web_search_tool_result","content":{"type":"web_search_tool_result_error","error_code":"unavailable"}}]}`
	srv := (&gateway{status: 200, body: body}).start(t)

	_, err := newSearcher(srv.URL).Search(context.Background(), "jwt", "q", 5)

	if err == nil || !strings.Contains(err.Error(), "temporarily unavailable") {
		t.Fatalf("err %v", err)
	}
}

type fakeSearcher struct {
	jwt   string
	query string
	max   int
}

func (f *fakeSearcher) Search(_ context.Context, callerJWT, query string, maxResults int) (*Result, error) {
	f.jwt, f.query, f.max = callerJWT, query, maxResults
	return &Result{Results: []Source{}, SearchedAt: "t"}, nil
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
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatalf("response %q: %v", rec.Body.String(), err)
	}
	return out["result"].(map[string]any)
}

func TestMCP_PublishesFinalToolName_WebSearch(t *testing.T) {
	t.Parallel()
	h := &MCPHandler{Searcher: &fakeSearcher{}, Version: "test", Log: quiet}

	res := mcpCall(t, h, "", `{"jsonrpc":"2.0","id":1,"method":"tools/list"}`)

	tools := res["tools"].([]any)
	if len(tools) != 1 || tools[0].(map[string]any)["name"] != "web_search" {
		t.Fatalf("tools %v", tools)
	}
}

func TestMCP_SearchesWithCallerToken_DefaultingToFiveResults(t *testing.T) {
	t.Parallel()
	s := &fakeSearcher{}
	h := &MCPHandler{Searcher: s, Version: "test", Log: quiet}

	res := mcpCall(t, h, "Bearer agent-jwt", `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"web_search","arguments":{"query":" grok "}}}`)

	if res["isError"] != false || s.jwt != "agent-jwt" || s.query != "grok" || s.max != 5 {
		t.Fatalf("res %v searcher %+v", res, s)
	}
}

func TestMCP_RefusesInvalidArguments_WithoutSearching(t *testing.T) {
	t.Parallel()
	cases := map[string]struct{ auth, args string }{
		"too many results": {"Bearer x", `{"query":"q","max_results":6}`},
		"empty query":      {"Bearer x", `{"query":"  "}`},
		"long query":       {"Bearer x", `{"query":"` + strings.Repeat("a", 401) + `"}`},
		"no caller token":  {"", `{"query":"q"}`},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			s := &fakeSearcher{}
			h := &MCPHandler{Searcher: s, Version: "test", Log: quiet}

			res := mcpCall(t, h, c.auth, `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"web_search","arguments":`+c.args+`}}`)

			if res["isError"] != true || s.query != "" {
				t.Fatalf("res %v", res)
			}
		})
	}
}
