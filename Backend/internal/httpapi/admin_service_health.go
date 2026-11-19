package httpapi

import (
	"context"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type adminServiceProbeTarget struct {
	name string
	base string
}

type serviceHealthItem struct {
	Name      string    `json:"name"`
	Status    string    `json:"status"`
	LatencyMS int64     `json:"latency_ms"`
	CheckedAt time.Time `json:"checked_at"`
	Error     string    `json:"error,omitempty"`
}

func (h *adminHandlers) serviceHealth(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.require(w, r, "dashboard.read"); !ok {
		return
	}

	targets := []adminServiceProbeTarget{
		{name: "identity", base: serviceBaseURL("IDENTITY_API_BASE", "http://127.0.0.1:8789")},
		{name: "game", base: serviceBaseURL("GAME_API_BASE", "http://127.0.0.1:8787")},
		{name: "chat", base: serviceBaseURL("CHAT_API_BASE", "http://127.0.0.1:8788")},
	}
	results := make([]serviceHealthItem, 4)
	results[0] = serviceHealthItem{Name: "admin", Status: "unhealthy", CheckedAt: time.Now().UTC()}
	adminCtx, adminCancel := context.WithTimeout(r.Context(), 2*time.Second)
	adminStarted := time.Now()
	if h.db != nil && h.db.PingContext(adminCtx) == nil {
		results[0].Status = "healthy"
	} else {
		results[0].Error = "Admin database unavailable"
	}
	results[0].LatencyMS = time.Since(adminStarted).Milliseconds()
	results[0].CheckedAt = time.Now().UTC()
	adminCancel()
	var wg sync.WaitGroup
	for i, probeTarget := range targets {
		wg.Add(1)
		go func(index int, dependency adminServiceProbeTarget) {
			defer wg.Done()
			results[index+1] = probeAdminDependency(r.Context(), dependency.name, dependency.base)
		}(i, probeTarget)
	}
	wg.Wait()

	overall := "healthy"
	for _, item := range results {
		if item.Status != "healthy" {
			overall = "degraded"
			break
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status": overall,
		"checked_at": time.Now().UTC(),
		"items": results,
	})
}

func serviceBaseURL(env, fallback string) string {
	value := strings.TrimRight(strings.TrimSpace(os.Getenv(env)), "/")
	if value == "" {
		return fallback
	}
	return value
}

func probeAdminDependency(parent context.Context, name, base string) serviceHealthItem {
	item := serviceHealthItem{Name: name, Status: "unhealthy", CheckedAt: time.Now().UTC()}
	ctx, cancel := context.WithTimeout(parent, 2500*time.Millisecond)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/ready", nil)
	if err != nil {
		item.Error = "invalid service URL"
		return item
	}
	client := &http.Client{
		Timeout: 2500 * time.Millisecond,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	started := time.Now()
	response, err := client.Do(request)
	item.LatencyMS = time.Since(started).Milliseconds()
	item.CheckedAt = time.Now().UTC()
	if err != nil {
		item.Error = "service unavailable or readiness timeout"
		return item
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		item.Error = "readiness endpoint returned HTTP " + response.Status
		return item
	}
	item.Status = "healthy"
	return item
}
