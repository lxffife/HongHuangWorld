package gameadmin

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var ErrUnavailable = errors.New("game administration service unavailable")

type Client struct {
	baseURL string
	apiKey string
	httpClient *http.Client
}

func New(baseURL, apiKey string) *Client {
	return &Client{
		baseURL: strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		apiKey: strings.TrimSpace(apiKey),
		httpClient: &http.Client{Timeout: 6 * time.Second},
	}
}

func (c *Client) ready() bool { return c.baseURL != "" && c.apiKey != "" }

func (c *Client) PlayerDetail(ctx context.Context, accountID string) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	endpoint := c.baseURL + "/api/v1/internal/admin/players/" + url.PathEscape(accountID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil { return nil, err }
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound { return nil, fmt.Errorf("game player not found") }
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}

func (c *Client) OnlinePlayers(ctx context.Context) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	endpoint := c.baseURL + "/api/v1/internal/admin/players/online"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil { return nil, err }
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}
func (c *Client) Worlds(ctx context.Context) (json.RawMessage, error) {
	return c.getAdminJSON(ctx, "/api/v1/internal/admin/worlds")
}

func (c *Client) WorldInstances(ctx context.Context, worldID string) (json.RawMessage, error) {
	return c.getAdminJSON(ctx, "/api/v1/internal/admin/worlds/"+url.PathEscape(worldID)+"/instances")
}

func (c *Client) SetWorldEnabled(ctx context.Context, worldID string, enabled bool) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	body, err := json.Marshal(map[string]bool{"enabled": enabled})
	if err != nil { return nil, err }
	endpoint := c.baseURL + "/api/v1/internal/admin/worlds/" + url.PathEscape(worldID) + "/state"
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, endpoint, bytes.NewReader(body))
	if err != nil { return nil, err }
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound { return nil, fmt.Errorf("world not found") }
	if resp.StatusCode == http.StatusBadRequest { return nil, fmt.Errorf("invalid world state") }
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}

func (c *Client) getAdminJSON(ctx context.Context, path string) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+path, nil)
	if err != nil { return nil, err }
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound { return nil, fmt.Errorf("world not found") }
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}

func (c *Client) ServerNodes(ctx context.Context) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/v1/internal/admin/servers/nodes", nil)
	if err != nil { return nil, err }
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}

func (c *Client) SetServerNodeState(ctx context.Context, nodeKey, state string) (json.RawMessage, error) {
	if !c.ready() { return nil, ErrUnavailable }
	body, err := json.Marshal(map[string]string{"admin_state": state})
	if err != nil { return nil, err }
	endpoint := c.baseURL + "/api/v1/internal/admin/servers/nodes/" + url.PathEscape(nodeKey) + "/state"
	req, err := http.NewRequestWithContext(ctx, http.MethodPatch, endpoint, bytes.NewReader(body))
	if err != nil { return nil, err }
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return nil, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound { return nil, fmt.Errorf("world server node not found") }
	if resp.StatusCode == http.StatusBadRequest { return nil, fmt.Errorf("invalid world server node state") }
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return nil, err }
	return result, nil
}
type DisconnectResult struct {
	Status string `json:"status"`
	RequestedSessions int64 `json:"requested_sessions"`
}

func (c *Client) DisconnectPlayer(ctx context.Context, accountID string) (DisconnectResult, error) {
	if !c.ready() { return DisconnectResult{}, ErrUnavailable }
	endpoint := c.baseURL + "/api/v1/internal/admin/players/" + url.PathEscape(accountID) + "/disconnect"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader([]byte("{}")))
	if err != nil { return DisconnectResult{}, err }
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Game-Admin-Key", c.apiKey)
	resp, err := c.httpClient.Do(req)
	if err != nil { return DisconnectResult{}, fmt.Errorf("%w: %v", ErrUnavailable, err) }
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusAccepted { return DisconnectResult{}, fmt.Errorf("%w: game returned %d", ErrUnavailable, resp.StatusCode) }
	var result DisconnectResult
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil { return DisconnectResult{}, err }
	return result, nil
}
