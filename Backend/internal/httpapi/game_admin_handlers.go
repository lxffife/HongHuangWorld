package httpapi

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
)

type gamePlayerAdminHandlers struct {
	db *sql.DB
	apiKey string
	logger *slog.Logger
	entryService *worldentry.Service
}

type adminPlayerSoul struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Karma int64 `json:"karma"`
	Merit int64 `json:"merit"`
}

type adminPlayerLife struct {
	ID string `json:"id"`
	Name string `json:"name"`
	LifeIndex int `json:"life_index"`
	WorldID string `json:"world_id"`
	WorldName string `json:"world_name"`
	Level int `json:"level"`
	Status string `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type adminPlayerWorldSession struct {
	ID string `json:"id"`
	State string `json:"state"`
	ConnectedAt time.Time `json:"connected_at"`
	WorldID string `json:"world_id"`
	ServerID string `json:"server_id"`
	NodeKey string `json:"node_key,omitempty"`
}

func (h *gamePlayerAdminHandlers) authorize(w http.ResponseWriter, r *http.Request) bool {
	provided := r.Header.Get("X-Game-Admin-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized service", http.StatusUnauthorized)
		return false
	}
	return true
}

func (h *gamePlayerAdminHandlers) detail(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	accountID := strings.TrimSpace(r.PathValue("accountID"))
	if accountID == "" || len(accountID) > 64 {
		http.Error(w, "invalid account id", http.StatusBadRequest)
		return
	}
	ctx := r.Context()
	var soul adminPlayerSoul
	var currentCharacterID sql.NullString
	err := h.db.QueryRowContext(ctx, `
		SELECT id::text, soul_name, karma, merit, current_character_id::text
		FROM souls WHERE account_id = $1::uuid
	`, accountID).Scan(&soul.ID, &soul.Name, &soul.Karma, &soul.Merit, &currentCharacterID)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusOK, map[string]any{"soul": nil, "current_character": nil, "lives": []adminPlayerLife{}, "active_sessions": []adminPlayerWorldSession{}})
		return
	}
	if err != nil {
		h.logger.Error("game admin player soul lookup failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	lives := make([]adminPlayerLife, 0)
	rows, err := h.db.QueryContext(ctx, `
		SELECT c.id::text, c.name, c.life_index, c.world_id, w.name,
		       c.level, c.status, c.created_at
		FROM characters c
		JOIN world_definitions w ON w.id = c.world_id
		WHERE c.soul_id = $1
		ORDER BY c.life_index DESC
		LIMIT 100
	`, soul.ID)
	if err != nil {
		h.logger.Error("game admin player lives query failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	for rows.Next() {
		var item adminPlayerLife
		if err := rows.Scan(&item.ID, &item.Name, &item.LifeIndex, &item.WorldID, &item.WorldName, &item.Level, &item.Status, &item.CreatedAt); err != nil {
			rows.Close()
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		lives = append(lives, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		h.logger.Error("game admin player lives iteration failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	rows.Close()

	var current any
	if currentCharacterID.Valid {
		for _, life := range lives {
			if life.ID == currentCharacterID.String {
				current = life
				break
			}
		}
	}
	sessions := make([]adminPlayerWorldSession, 0)
	sessionRows, err := h.db.QueryContext(ctx, `
		SELECT ws.id::text, ws.session_state, ws.connected_at, c.world_id,
		       ws.server_id::text, COALESCE(sr.node_key, '')
		FROM world_sessions ws
		JOIN characters c ON c.id = ws.character_id
		LEFT JOIN server_registry sr ON sr.id = ws.server_id
		WHERE c.soul_id = $1 AND ws.session_state IN ('connecting', 'active', 'saving')
		ORDER BY ws.connected_at DESC
		LIMIT 20
	`, soul.ID)
	if err != nil {
		h.logger.Error("game admin player sessions query failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	for sessionRows.Next() {
		var item adminPlayerWorldSession
		if err := sessionRows.Scan(&item.ID, &item.State, &item.ConnectedAt, &item.WorldID, &item.ServerID, &item.NodeKey); err != nil {
			sessionRows.Close()
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		sessions = append(sessions, item)
	}
	if err := sessionRows.Err(); err != nil {
		sessionRows.Close()
		h.logger.Error("game admin player sessions iteration failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	sessionRows.Close()

	writeJSON(w, http.StatusOK, map[string]any{
		"soul": soul, "current_character": current, "lives": lives, "active_sessions": sessions,
	})
}


func (h *gamePlayerAdminHandlers) disconnect(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	accountID := strings.TrimSpace(r.PathValue("accountID"))
	if accountID == "" || len(accountID) > 64 {
		http.Error(w, "invalid account id", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	count, err := h.entryService.RequestDisconnect(ctx, accountID)
	if err != nil {
		h.logger.Error("game admin player disconnect request failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"status": "disconnect_requested",
		"requested_sessions": count,
	})
}

func registerGamePlayerAdminRoutes(mux *http.ServeMux, db *sql.DB, logger *slog.Logger) {
	h := &gamePlayerAdminHandlers{db: db, apiKey: strings.TrimSpace(os.Getenv("GAME_ADMIN_INTERNAL_API_KEY")), logger: logger, entryService: worldentry.NewService(db)}
	mux.HandleFunc("GET /api/v1/internal/admin/players/{accountID}", h.detail)
	mux.HandleFunc("POST /api/v1/internal/admin/players/{accountID}/disconnect", h.disconnect)
}
