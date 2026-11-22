package oidc

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func tokenServer(t *testing.T, calls *atomic.Int32, check func(r *http.Request)) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		_ = r.ParseForm()
		if check != nil {
			check(r)
		}
		if r.PostForm.Get("client_secret") != "s3cret" {
			w.WriteHeader(http.StatusUnauthorized)
			fmt.Fprint(w, `{"error":"unauthorized_client"}`)
			return
		}
		fmt.Fprintf(w, `{"access_token":"tok-%d","expires_in":300}`, n)
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

func TestCachedSource_ReusesToken_UntilOneMinuteBeforeExpiry(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	now := time.Unix(1_000_000, 0)
	client := &Client{TokenURL: tokenServer(t, &calls, nil), ClientID: "agent-p-a", ClientSecret: "s3cret", Now: func() time.Time { return now }}
	src := &CachedSource{Client: client, RefreshBefore: time.Minute}

	first, _ := src.Token(context.Background())
	now = now.Add(239 * time.Second)
	cached, _ := src.Token(context.Background())
	now = now.Add(2 * time.Second)
	renewed, err := src.Token(context.Background())

	if err != nil || first != "tok-1" || cached != "tok-1" || renewed != "tok-2" {
		t.Fatalf("tokens %q %q %q, err %v", first, cached, renewed, err)
	}
}

func TestClientCredentials_ReturnsError_WhenSecretIsWrong(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	client := &Client{TokenURL: tokenServer(t, &calls, nil), ClientID: "agent-p-a", ClientSecret: "wrong"}

	_, err := client.ClientCredentials(context.Background())

	if err == nil {
		t.Fatal("expected an error")
	}
}

func TestExchange_SendsSubjectAudienceAndScope(t *testing.T) {
	t.Parallel()
	var calls atomic.Int32
	var form map[string]string
	url := tokenServer(t, &calls, func(r *http.Request) {
		form = map[string]string{}
		for _, k := range []string{"grant_type", "subject_token", "audience", "scope", "client_id"} {
			form[k] = r.PostForm.Get(k)
		}
	})
	client := &Client{TokenURL: url, ClientID: "sandbox-runner", ClientSecret: "s3cret"}

	_, err := client.Exchange(context.Background(), "agent-jwt", "ai-gateway", "mcp-read")

	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"grant_type": "urn:ietf:params:oauth:grant-type:token-exchange", "subject_token": "agent-jwt",
		"audience": "ai-gateway", "scope": "mcp-read", "client_id": "sandbox-runner"}
	for k, v := range want {
		if form[k] != v {
			t.Fatalf("%s = %q, want %q", k, form[k], v)
		}
	}
}

func TestUnverifiedClaims_DecodesPayload(t *testing.T) {
	t.Parallel()
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"azp":"agent-p-a","project":["p"]}`))

	claims, err := UnverifiedClaims("h." + payload + ".sig")

	if err != nil || claims["azp"] != "agent-p-a" {
		t.Fatalf("claims %v, err %v", claims, err)
	}
}
