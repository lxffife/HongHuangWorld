package auth

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"
)

type Provider interface {
	Register(context.Context, string, string, string) (Account, string, time.Time, error)
	Login(context.Context, string, string) (Account, string, time.Time, error)
	Authenticate(context.Context, string) (Account, error)
}

type identityCacheEntry struct {
	account Account
	expiresAt time.Time
}

type HTTPClient struct {
	baseURL string
	serviceKey string
	client *http.Client
	mu sync.Mutex
	cache map[[32]byte]identityCacheEntry
}

func NewHTTPClient(baseURL, serviceKey string) *HTTPClient {
	return &HTTPClient{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		serviceKey: strings.TrimSpace(serviceKey),
		client: &http.Client{Timeout: 4 * time.Second},
		cache: make(map[[32]byte]identityCacheEntry),
	}
}

type credentialsRequest struct {
	Username string `json:"username"`
	Email string `json:"email,omitempty"`
	Password string `json:"password"`
}

type sessionResponse struct {
	Account Account `json:"account"`
	Token string `json:"access_token"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (c *HTTPClient) Register(ctx context.Context, username, email, password string) (Account, string, time.Time, error) {
	return c.createSession(ctx, "/api/v1/auth/register", credentialsRequest{Username:username, Email:email, Password:password})
}

func (c *HTTPClient) Login(ctx context.Context, username, password string) (Account, string, time.Time, error) {
	return c.createSession(ctx, "/api/v1/auth/login", credentialsRequest{Username:username, Password:password})
}

func (c *HTTPClient) createSession(ctx context.Context, path string, payload credentialsRequest) (Account, string, time.Time, error) {
	var result sessionResponse
	status, err := c.doJSON(ctx, http.MethodPost, path, payload, "", &result)
	if err != nil { return Account{}, "", time.Time{}, err }
	switch status {
	case http.StatusCreated, http.StatusOK:
		return result.Account, result.Token, result.ExpiresAt, nil
	case http.StatusBadRequest:
		return Account{}, "", time.Time{}, ErrInvalidInput
	case http.StatusConflict:
		return Account{}, "", time.Time{}, ErrConflict
	case http.StatusUnauthorized:
		return Account{}, "", time.Time{}, ErrInvalidCredentials
	default:
		return Account{}, "", time.Time{}, fmt.Errorf("identity service returned status %d", status)
	}
}

func (c *HTTPClient) Authenticate(ctx context.Context, token string) (Account, error) {
	if token == "" || len(token) > 128 || c.serviceKey == "" {
		return Account{}, ErrUnauthorized
	}
	cacheKey := sha256.Sum256([]byte(token))
	now := time.Now()
	c.mu.Lock()
	if cached, ok := c.cache[cacheKey]; ok && now.Before(cached.expiresAt) {
		c.mu.Unlock()
		return cached.account, nil
	}
	c.mu.Unlock()

	var account Account
	status, err := c.doJSON(ctx, http.MethodPost, "/api/v1/internal/auth/introspect", nil, token, &account)
	if err != nil {
		c.mu.Lock()
		cached, ok := c.cache[cacheKey]
		c.mu.Unlock()
		if ok && now.Before(cached.expiresAt) {
			return cached.account, nil
		}
		return Account{}, err
	}
	if status != http.StatusOK {
		c.mu.Lock()
		delete(c.cache, cacheKey)
		c.mu.Unlock()
		return Account{}, ErrUnauthorized
	}
	c.mu.Lock()
	if len(c.cache) >= 4096 {
		for key, entry := range c.cache {
			if !now.Before(entry.expiresAt) { delete(c.cache, key) }
		}
		if len(c.cache) >= 4096 {
			for key := range c.cache { delete(c.cache, key); break }
		}
	}
	c.cache[cacheKey] = identityCacheEntry{account: account, expiresAt: now.Add(15 * time.Second)}
	c.mu.Unlock()
	return account, nil
}

func (c *HTTPClient) doJSON(ctx context.Context, method, path string, payload any, bearer string, target any) (int, error) {
	if c.baseURL == "" { return 0, errors.New("identity API base URL is not configured") }
	var body bytes.Buffer
	if payload != nil {
		if err := json.NewEncoder(&body).Encode(payload); err != nil { return 0, err }
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, &body)
	if err != nil { return 0, err }
	if payload != nil { req.Header.Set("Content-Type", "application/json") }
	if bearer != "" { req.Header.Set("Authorization", "Bearer "+bearer) }
	if c.serviceKey != "" { req.Header.Set("X-Identity-Service-Key", c.serviceKey) }
	resp, err := c.client.Do(req)
	if err != nil { return 0, fmt.Errorf("identity service request failed: %w", err) }
	defer resp.Body.Close()
	if resp.StatusCode >= 500 { return resp.StatusCode, fmt.Errorf("identity service unavailable (status %d)", resp.StatusCode) }
	if target != nil && resp.StatusCode >= 200 && resp.StatusCode < 300 {
		if err := json.NewDecoder(resp.Body).Decode(target); err != nil { return resp.StatusCode, fmt.Errorf("decode identity response: %w", err) }
	}
	return resp.StatusCode, nil
}
