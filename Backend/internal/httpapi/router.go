package httpapi

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
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
		authService := auth.NewService(db)
		handlers := &authHandlers{service: authService, logger: logger}
		mux.HandleFunc("POST /api/v1/auth/register", handlers.register)
		mux.HandleFunc("POST /api/v1/auth/login", handlers.login)
		mux.HandleFunc("GET /api/v1/account/me", handlers.me)
		souls := &soulHandlers{authService: authService, soulService: soul.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/souls", souls.create)
		mux.HandleFunc("GET /api/v1/souls/current", souls.current)
		mux.HandleFunc("GET /api/v1/souls/current/progression", souls.progression)
		mux.HandleFunc("GET /api/v1/souls/current/fate", souls.fate)
		mux.HandleFunc("POST /api/v1/souls/current/breakthrough", souls.breakthrough)
		mux.HandleFunc("GET /api/v1/souls/current/trials", souls.trials)
		mux.HandleFunc("GET /api/v1/souls/current/reincarnation-eligibility", souls.reincarnationEligibility)
		mux.HandleFunc("POST /api/v1/servers/souls/rewards", souls.applyReward)
		worlds := &worldHandlers{service: world.NewService(db), logger: logger}
		npcs := &npcHandlers{authService: authService, service: npc.NewService(db), logger: logger}
		mux.HandleFunc("GET /api/v1/worlds/current/npcs", npcs.list)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/interact", npcs.interact)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/choose", npcs.chooseFate)
		mux.HandleFunc("POST /api/v1/worlds/current/npcs/discover", npcs.discoverFateEncounter)
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
		for _, route := range []string{
			"POST /api/v1/auth/register", "POST /api/v1/auth/login", "GET /api/v1/account/me",
			"POST /api/v1/souls", "GET /api/v1/souls/current", "GET /api/v1/souls/current/progression", "POST /api/v1/souls/current/breakthrough", "GET /api/v1/souls/current/trials", "GET /api/v1/souls/current/reincarnation-eligibility", "POST /api/v1/servers/souls/rewards", "GET /api/v1/worlds", "GET /api/v1/worlds/current/npcs", "POST /api/v1/worlds/current/npcs/interact", "POST /api/v1/worlds/current/npcs/choose", "POST /api/v1/worlds/current/npcs/discover",
			"GET /api/v1/worlds/current/exploration-points", "POST /api/v1/worlds/current/exploration-points/discover", "GET /api/v1/worlds/current/exploration-events", "POST /api/v1/worlds/current/exploration-events/trigger",
			"GET /api/v1/cultivation/systems", "GET /api/v1/cultivation/race-growth",
			"GET /api/v1/cultivation/bloodlines", "GET /api/v1/cultivation/techniques",
			"POST /api/v1/characters/first-life", "GET /api/v1/characters/current/reincarnation-routes", "GET /api/v1/characters/current", "POST /api/v1/characters/current/respawn", "POST /api/v1/characters/current/reincarnate",
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

func requestLogger(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("http request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(started).Milliseconds())
	})
}
