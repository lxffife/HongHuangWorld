package httpapi

import (
	"bufio"
	"fmt"
	"net"
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
	"github.com/liflife/HongHuangWorld/Backend/internal/character"
	"github.com/liflife/HongHuangWorld/Backend/internal/inventory"
	"github.com/liflife/HongHuangWorld/Backend/internal/npc"
	"github.com/liflife/HongHuangWorld/Backend/internal/soul"
	"github.com/liflife/HongHuangWorld/Backend/internal/serverregistry"
	"github.com/liflife/HongHuangWorld/Backend/internal/world"
	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
)

type healthResponse struct {
	Status string `json:"status"`
	Time   string `json:"time"`
}

func NewRouter(logger *slog.Logger, db *sql.DB) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{Status: "ok", Time: time.Now().UTC().Format(time.RFC3339)})
	})
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, r *http.Request) {
		if db == nil { http.Error(w, "database is not configured", http.StatusServiceUnavailable); return }
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.PingContext(ctx); err != nil {
			logger.Warn("readiness check failed", "error", err)
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, healthResponse{Status: "ready", Time: time.Now().UTC().Format(time.RFC3339)})
	})

	if db != nil {
		registerGamePlayerAdminRoutes(mux, db, logger)
		authService := configuredAuthProvider()
		handlers := &authHandlers{service: authService, logger: logger}
		chatAPI := &chatHandlers{authService: authService, service: chat.NewService(db), logger: logger}
		mux.HandleFunc("POST /api/v1/chat/messages", chatAPI.send)
		mux.HandleFunc("GET /api/v1/chat/messages", chatAPI.list)
		chatServerAPI := &chatServerHandlers{service: chat.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("GET /api/v1/servers/chat/messages", chatServerAPI.poll)
		mux.HandleFunc("POST /api/v1/servers/chat/messages", chatServerAPI.publish)
		mux.HandleFunc("POST /api/v1/auth/register", handlers.register)
		mux.HandleFunc("POST /api/v1/auth/login", handlers.login)
		mux.HandleFunc("GET /api/v1/account/me", handlers.me)
		souls := &soulHandlers{authService: authService, soulService: soul.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/souls", souls.create)
		mux.HandleFunc("GET /api/v1/souls/current", souls.current)
		mux.HandleFunc("GET /api/v1/souls/current/essence", souls.essence)
		mux.HandleFunc("GET /api/v1/souls/current/fusions", souls.fusions)
		mux.HandleFunc("POST /api/v1/souls/current/fusions", souls.fuse)
		mux.HandleFunc("POST /api/v1/souls/current/essence/allocate", souls.allocateRareEssence)
		mux.HandleFunc("GET /api/v1/souls/current/progression", souls.progression)
		mux.HandleFunc("GET /api/v1/souls/current/fate", souls.fate)
		mux.HandleFunc("POST /api/v1/souls/current/breakthrough", souls.breakthrough)
		mux.HandleFunc("GET /api/v1/souls/current/trials", souls.trials)
		mux.HandleFunc("GET /api/v1/souls/current/reincarnation-eligibility", souls.reincarnationEligibility)
		mux.HandleFunc("POST /api/v1/servers/souls/rewards", souls.applyReward)
		mux.HandleFunc("POST /api/v1/servers/souls/absorptions", souls.applyAbsorption)
		worlds := &worldHandlers{service: world.NewService(db), logger: logger}
		npcs := &npcHandlers{authService: authService, service: npc.NewService(db), logger: logger}
		mux.HandleFunc("GET /api/v1/worlds/current/npcs", npcs.list)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/interact", npcs.interact)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/choose", npcs.chooseFate)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/discover", npcs.discoverFateEncounter)
		mux.HandleFunc("GET /api/v1/worlds/current/exploration-progress", npcs.explorationProgress)
		mux.HandleFunc("GET /api/v1/worlds/current/exploration-points", npcs.listExplorationPoints)
		mux.HandleFunc("POST /api/v1/worlds/current/exploration-points/discover", npcs.discoverExplorationPoint)
		mux.HandleFunc("GET /api/v1/worlds/current/exploration-events", npcs.listExplorationEvents)
		mux.HandleFunc("POST /api/v1/worlds/current/exploration-events/trigger", npcs.triggerExplorationEvent)
		mux.HandleFunc("GET /api/v1/worlds", worlds.list)
		characters := &characterHandlers{authService: authService, characterService: character.NewService(db), logger: logger}
		mux.HandleFunc("GET /api/v1/cultivation/systems", characters.catalog)
		mux.HandleFunc("GET /api/v1/cultivation/race-growth", characters.growthProfiles)
		mux.HandleFunc("GET /api/v1/cultivation/bloodlines", characters.bloodlines)
		mux.HandleFunc("GET /api/v1/cultivation/techniques", characters.techniques)
		mux.HandleFunc("POST /api/v1/characters/first-life", characters.createFirstLife)
		mux.HandleFunc("GET /api/v1/characters/current/reincarnation-routes", characters.reincarnationRoutes)
		mux.HandleFunc("GET /api/v1/characters/current/reincarnation-preview", characters.reincarnationPreview)
		mux.HandleFunc("POST /api/v1/characters/current/reincarnate", characters.reincarnate)
		mux.HandleFunc("GET /api/v1/characters/current", characters.current)
		mux.HandleFunc("GET /api/v1/souls/current/lives", characters.history)
		mux.HandleFunc("GET /api/v1/souls/current/memories", characters.memories)
		mux.HandleFunc("GET /api/v1/characters/current/status", characters.currentStatus)
		mux.HandleFunc("POST /api/v1/characters/current/breakthrough", characters.breakthrough)
		mux.HandleFunc("POST /api/v1/characters/current/bloodlines/awaken", characters.awakenBloodline)
		mux.HandleFunc("POST /api/v1/characters/current/techniques/train", characters.trainTechnique)
		mux.HandleFunc("POST /api/v1/characters/current/attributes/allocate", characters.allocateAttributePoints)
		items := &inventoryHandlers{authService: authService, service: inventory.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("GET /api/v1/items", items.catalog)
		mux.HandleFunc("GET /api/v1/characters/current/inventory", items.current)
		mux.HandleFunc("GET /api/v1/characters/current/equipment", items.equipment)
		mux.HandleFunc("POST /api/v1/characters/current/equipment/equip", items.equip)
		mux.HandleFunc("POST /api/v1/characters/current/equipment/unequip", items.unequip)
		mux.HandleFunc("POST /api/v1/characters/current/inventory/use", items.useConsumable)
		mux.HandleFunc("POST /api/v1/servers/sessions/combat-stats", items.sessionCombatStats)
		mux.HandleFunc("GET /api/v1/servers/loot-table", items.lootTable)
		mux.HandleFunc("GET /api/v1/servers/drops", items.listDrops)
		mux.HandleFunc("POST /api/v1/servers/drops", items.createDrop)
		mux.HandleFunc("POST /api/v1/servers/drops/pickup", items.pickupDrop)
		servers := &serverHandlers{service: serverregistry.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/servers/heartbeat", servers.heartbeat)
		rewards := &characterRewardHandlers{characterService: character.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/servers/characters/rewards", rewards.apply)
		entry := &worldEntryHandlers{authService: authService, entryService: worldentry.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/worlds/enter", entry.issue)
		mux.HandleFunc("POST /api/v1/characters/current/respawn", entry.respawn)
		mux.HandleFunc("POST /api/v1/servers/tickets/redeem", entry.redeem)
		mux.HandleFunc("POST /api/v1/servers/sessions/snapshot", entry.saveSnapshot)
		mux.HandleFunc("POST /api/v1/servers/sessions/close", entry.closeSession)
	} else {
		unavailable := func(w http.ResponseWriter, _ *http.Request) { http.Error(w, "service unavailable", http.StatusServiceUnavailable) }
		mux.HandleFunc("GET /api/v1/internal/admin/game-config/{resource}", unavailable)
		mux.HandleFunc("PATCH /api/v1/internal/admin/game-config/{resource}/{id}/state", unavailable)
		mux.HandleFunc("GET /api/v1/internal/admin/worlds", unavailable)
		mux.HandleFunc("GET /api/v1/internal/admin/worlds/{worldID}/instances", unavailable)
		mux.HandleFunc("PATCH /api/v1/internal/admin/worlds/{worldID}/state", unavailable)
		mux.HandleFunc("GET /api/v1/internal/admin/servers/nodes", unavailable)
		mux.HandleFunc("PATCH /api/v1/internal/admin/servers/nodes/{nodeKey}/state", unavailable)
		mux.HandleFunc("GET /api/v1/internal/admin/players/online", unavailable)
		mux.HandleFunc("GET /api/v1/internal/admin/players/{accountID}", unavailable)
		mux.HandleFunc("POST /api/v1/internal/admin/players/{accountID}/disconnect", unavailable)
		for _, route := range []string{
			"POST /api/v1/auth/register", "POST /api/v1/auth/login", "GET /api/v1/account/me",
			"POST /api/v1/chat/messages", "GET /api/v1/chat/messages", "GET /api/v1/servers/chat/messages", "POST /api/v1/servers/chat/messages",
			"POST /api/v1/souls", "GET /api/v1/souls/current", "GET /api/v1/souls/current/essence", "GET /api/v1/souls/current/fusions", "POST /api/v1/souls/current/fusions", "GET /api/v1/souls/current/progression", "POST /api/v1/souls/current/breakthrough", "GET /api/v1/souls/current/trials", "GET /api/v1/souls/current/reincarnation-eligibility", "POST /api/v1/servers/souls/rewards", "GET /api/v1/worlds", "GET /api/v1/worlds/current/npcs", "POST /api/v1/worlds/current/npcs/interact", "POST /api/v1/worlds/current/npcs/choose", "POST /api/v1/worlds/current/npcs/discover",
			"GET /api/v1/worlds/current/exploration-progress", "GET /api/v1/worlds/current/exploration-points", "POST /api/v1/worlds/current/exploration-points/discover", "GET /api/v1/worlds/current/exploration-events", "POST /api/v1/worlds/current/exploration-events/trigger",
			"GET /api/v1/cultivation/systems", "GET /api/v1/cultivation/race-growth",
			"GET /api/v1/cultivation/bloodlines", "GET /api/v1/cultivation/techniques",
			"POST /api/v1/characters/first-life", "GET /api/v1/characters/current/reincarnation-routes", "GET /api/v1/characters/current/reincarnation-preview", "GET /api/v1/characters/current", "POST /api/v1/characters/current/respawn", "POST /api/v1/characters/current/reincarnate",
			"GET /api/v1/characters/current/status", "POST /api/v1/characters/current/breakthrough",
			"POST /api/v1/characters/current/bloodlines/awaken", "POST /api/v1/characters/current/techniques/train",
			"POST /api/v1/characters/current/attributes/allocate", "GET /api/v1/items",
			"GET /api/v1/characters/current/inventory", "GET /api/v1/characters/current/equipment",
			"POST /api/v1/characters/current/equipment/equip", "POST /api/v1/characters/current/equipment/unequip", "POST /api/v1/characters/current/inventory/use", "POST /api/v1/servers/sessions/combat-stats", "GET /api/v1/servers/loot-table", "GET /api/v1/servers/drops", "POST /api/v1/servers/drops",
			"POST /api/v1/servers/drops/pickup", "POST /api/v1/servers/heartbeat",
			"POST /api/v1/servers/characters/rewards", "POST /api/v1/worlds/enter",
			"POST /api/v1/servers/tickets/redeem", "POST /api/v1/servers/sessions/snapshot",
			"POST /api/v1/servers/sessions/close",
		} { mux.HandleFunc(route, unavailable) }
	}
	return requestLogger(logger, mux)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes int
}

func (w *statusRecorder) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := w.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, fmt.Errorf("underlying response writer does not support hijacking")
	}
	conn, rw, err := hijacker.Hijack()
	if err == nil && w.status == 0 {
		w.status = http.StatusSwitchingProtocols
	}
	return conn, rw, err
}

func (w *statusRecorder) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

func (w *statusRecorder) WriteHeader(status int) {
	if w.status != 0 { return }
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusRecorder) Write(data []byte) (int, error) {
	if w.status == 0 { w.WriteHeader(http.StatusOK) }
	n, err := w.ResponseWriter.Write(data)
	w.bytes += n
	return n, err
}

func requestLogger(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w}
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.Error("http handler panic", "method", r.Method, "path", r.URL.Path, "panic", recovered)
				if recorder.status == 0 { http.Error(recorder, "internal server error", http.StatusInternalServerError) }
			}
			status := recorder.status
			if status == 0 { status = http.StatusOK }
			attrs := []any{"method", r.Method, "path", r.URL.Path, "status", status, "bytes", recorder.bytes, "duration_ms", time.Since(started).Milliseconds(), "remote", r.RemoteAddr}
			if status >= 500 { logger.Error("http request", attrs...) } else if status >= 400 { logger.Warn("http request", attrs...) } else { logger.Info("http request", attrs...) }
		}()
		next.ServeHTTP(recorder, r)
	})
}
