// Package oidc talks to the Keycloak token endpoint: client_credentials for an
// agent's own token and RFC 8693 token exchange for the sandbox's down-scoped one.
package oidc

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Token is an access token and the instant it stops being valid.
type Token struct {
	AccessToken string
	Expiry      time.Time
}

// Client holds one confidential client's credentials.
type Client struct {
	TokenURL     string
	ClientID     string
	ClientSecret string
	HTTP         *http.Client
	Now          func() time.Time
}

type tokenResponse struct {
	AccessToken      string `json:"access_token"`
	ExpiresIn        int    `json:"expires_in"`
	Error            string `json:"error"`
	ErrorDescription string `json:"error_description"`
}

func (c *Client) now() time.Time {
	if c.Now != nil {
		return c.Now()
	}
	return time.Now()
}

func (c *Client) post(ctx context.Context, form url.Values) (Token, error) {
	form.Set("client_id", c.ClientID)
	form.Set("client_secret", c.ClientSecret)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.TokenURL, strings.NewReader(form.Encode()))
	if err != nil {
		return Token{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	httpClient := c.HTTP
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 10 * time.Second}
	}
	start := c.now()
	resp, err := httpClient.Do(req)
	if err != nil {
		return Token{}, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return Token{}, err
	}
	var tr tokenResponse
	if err := json.Unmarshal(body, &tr); err != nil {
		return Token{}, fmt.Errorf("token endpoint answered %d with a non-JSON body", resp.StatusCode)
	}
	if resp.StatusCode != http.StatusOK || tr.AccessToken == "" {
		return Token{}, fmt.Errorf("token endpoint answered %d: %s %s", resp.StatusCode, tr.Error, tr.ErrorDescription)
	}
	if tr.ExpiresIn <= 0 {
		return Token{}, errors.New("token endpoint returned no expires_in")
	}
	return Token{AccessToken: tr.AccessToken, Expiry: start.Add(time.Duration(tr.ExpiresIn) * time.Second)}, nil
}

// ClientCredentials fetches a token for the client itself.
func (c *Client) ClientCredentials(ctx context.Context) (Token, error) {
	return c.post(ctx, url.Values{"grant_type": {"client_credentials"}})
}

// Exchange trades subjectToken for a token of this client, limited to audience and scope.
func (c *Client) Exchange(ctx context.Context, subjectToken, audience, scope string) (Token, error) {
	return c.post(ctx, url.Values{
		"grant_type":           {"urn:ietf:params:oauth:grant-type:token-exchange"},
		"subject_token":        {subjectToken},
		"subject_token_type":   {"urn:ietf:params:oauth:token-type:access_token"},
		"requested_token_type": {"urn:ietf:params:oauth:token-type:access_token"},
		"audience":             {audience},
		"scope":                {scope},
	})
}

// CachedSource hands out the client's token and fetches a new one once fewer
// than RefreshBefore remain, so callers never send a token about to expire.
type CachedSource struct {
	Client        *Client
	RefreshBefore time.Duration

	mu  sync.Mutex
	tok Token
}

// Token returns a token valid for at least RefreshBefore.
func (s *CachedSource) Token(ctx context.Context) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.tok.AccessToken != "" && s.Client.now().Add(s.RefreshBefore).Before(s.tok.Expiry) {
		return s.tok.AccessToken, nil
	}
	tok, err := s.Client.ClientCredentials(ctx)
	if err != nil {
		return "", fmt.Errorf("client_credentials for %s: %w", s.Client.ClientID, err)
	}
	s.tok = tok
	return tok.AccessToken, nil
}

// UnverifiedClaims decodes a JWT payload without checking its signature. Only
// for tokens the AI gateway has already verified before forwarding them.
func UnverifiedClaims(jwt string) (map[string]any, error) {
	parts := strings.Split(jwt, ".")
	if len(parts) != 3 {
		return nil, errors.New("not a JWT")
	}
	payload, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(parts[1], "="))
	if err != nil {
		return nil, fmt.Errorf("JWT payload: %w", err)
	}
	claims := map[string]any{}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return nil, fmt.Errorf("JWT payload: %w", err)
	}
	return claims, nil
}
