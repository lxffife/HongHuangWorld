package httpapi

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
	"github.com/liflife/HongHuangWorld/Backend/internal/serverregistry"
)

type gamePlayerAdminHandlers struct {
	db *sql.DB
	apiKey string
	logger *slog.Logger
	entryService *worldentry.Service
	serverService *serverregistry.Service
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


type adminOnlinePlayer struct {
	AccountID string `json:"account_id"`
	CharacterID string `json:"character_id"`
	CharacterName string `json:"character_name"`
	Level int `json:"level"`
	WorldID string `json:"world_id"`
	WorldName string `json:"world_name"`
	SessionID string `json:"session_id"`
	ConnectedAt time.Time `json:"connected_at"`
	NodeKey string `json:"node_key"`
	Host string `json:"host"`
	UDPPort int `json:"udp_port"`
	Region string `json:"region"`
	NodeStatus string `json:"node_status"`
	HeartbeatAt time.Time `json:"heartbeat_at"`
	Capacity int `json:"capacity"`
	CurrentPlayers int `json:"current_players"`
}

func (h *gamePlayerAdminHandlers) online(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	rows, err := h.db.QueryContext(ctx, `
		SELECT COUNT(*) OVER(), soul.account_id::text, c.id::text, c.name, c.level, c.world_id,
		       wd.name, ws.id::text, ws.connected_at, sr.node_key, sr.host,
		       sr.udp_port, sr.region, CASE WHEN sr.admin_state = 'disabled' THEN 'offline' WHEN sr.admin_state = 'draining' THEN 'draining' WHEN sr.last_heartbeat_at IS NULL OR sr.last_heartbeat_at < now() - interval '30 seconds' THEN 'offline' ELSE sr.status END, sr.last_heartbeat_at, sr.capacity, sr.current_players
		FROM world_sessions ws
		JOIN characters c ON c.id = ws.character_id
		JOIN souls soul ON soul.id = c.soul_id
		JOIN world_definitions wd ON wd.id = c.world_id
		JOIN server_registry sr ON sr.id = ws.server_id
		WHERE ws.session_state = 'active'
		ORDER BY ws.connected_at DESC
		LIMIT 500
	`)
	if err != nil {
		h.logger.Error("game admin online players query failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	items := make([]adminOnlinePlayer, 0)
	var total int64
	for rows.Next() {
		var item adminOnlinePlayer
		if err := rows.Scan(&total, &item.AccountID, &item.CharacterID, &item.CharacterName, &item.Level, &item.WorldID, &item.WorldName, &item.SessionID, &item.ConnectedAt, &item.NodeKey, &item.Host, &item.UDPPort, &item.Region, &item.NodeStatus, &item.HeartbeatAt, &item.Capacity, &item.CurrentPlayers); err != nil {
			h.logger.Error("scan game admin online player failed", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate game admin online players failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "total": total, "returned": len(items), "limit": 500})
}
func (h *gamePlayerAdminHandlers) listServerNodes(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	nodes, err := h.serverService.ListNodes(ctx)
	if err != nil {
		h.logger.Error("game admin server node list failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": nodes, "total": len(nodes)})
}

func (h *gamePlayerAdminHandlers) setServerNodeState(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	var request struct { AdminState string `json:"admin_state"` }
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	requested, err := h.serverService.SetAdminState(ctx, r.PathValue("nodeKey"), request.AdminState)
	if errors.Is(err, serverregistry.ErrInvalidNodeState) { http.Error(w, "admin_state must be normal, draining or disabled", http.StatusBadRequest); return }
	if errors.Is(err, serverregistry.ErrNodeNotFound) { http.Error(w, "world server node not found", http.StatusNotFound); return }
	if err != nil {
		h.logger.Error("game admin server node state update failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"node_key": r.PathValue("nodeKey"), "admin_state": request.AdminState, "requested_disconnects": requested})
}
type adminWorld struct {
	ID string `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
	Level int16 `json:"level"`
	Enabled bool `json:"enabled"`
	InstanceCount int `json:"instance_count"`
	ReadyInstances int `json:"ready_instances"`
	ActiveSessions int `json:"active_sessions"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type adminWorldInstance struct {
	ID string `json:"id"`
	InstanceKey string `json:"instance_key"`
	Status string `json:"status"`
	EffectiveStatus string `json:"effective_status"`
	NodeKey string `json:"node_key"`
	Host string `json:"host"`
	UDPPort int `json:"udp_port"`
	Region string `json:"region"`
	LastHeartbeatAt *time.Time `json:"last_heartbeat_at"`
	ActiveSessions int `json:"active_sessions"`
	PendingSessions int `json:"pending_sessions"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (h *gamePlayerAdminHandlers) listWorlds(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	rows, err := h.db.QueryContext(ctx, `
		SELECT wd.id, wd.name, wd.world_type, wd.world_level, wd.enabled,
		       COUNT(DISTINCT wi.id)::int,
		       COUNT(DISTINCT wi.id) FILTER (WHERE wi.status = 'ready' AND sr.admin_state = 'normal' AND sr.last_heartbeat_at > now() - interval '30 seconds')::int,
		       COUNT(DISTINCT ws.id) FILTER (WHERE ws.session_state = 'active')::int,
		       wd.created_at, wd.updated_at
		FROM world_definitions wd
		LEFT JOIN world_instances wi ON wi.world_id = wd.id
		LEFT JOIN server_registry sr ON sr.id = wi.server_id
		LEFT JOIN world_sessions ws ON ws.instance_id = wi.id
		GROUP BY wd.id
		ORDER BY wd.world_level, wd.id
	`)
	if err != nil {
		h.logger.Error("game admin worlds query failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	items := make([]adminWorld, 0)
	for rows.Next() {
		var item adminWorld
		if err := rows.Scan(&item.ID, &item.Name, &item.Type, &item.Level, &item.Enabled, &item.InstanceCount, &item.ReadyInstances, &item.ActiveSessions, &item.CreatedAt, &item.UpdatedAt); err != nil {
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate game admin worlds failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "total": len(items)})
}

func (h *gamePlayerAdminHandlers) listWorldInstances(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	worldID := strings.TrimSpace(r.PathValue("worldID"))
	if worldID == "" || len(worldID) > 64 {
		http.Error(w, "invalid world id", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Second)
	defer cancel()
	var exists bool
	if err := h.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM world_definitions WHERE id = $1)`, worldID).Scan(&exists); err != nil {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if !exists { http.Error(w, "world not found", http.StatusNotFound); return }
	rows, err := h.db.QueryContext(ctx, `
		SELECT wi.id::text, wi.instance_key, wi.status,
		       CASE WHEN wd.enabled = FALSE OR sr.admin_state = 'disabled' THEN 'offline'
		            WHEN sr.admin_state = 'draining' OR wi.status = 'draining' THEN 'draining'
		            WHEN sr.last_heartbeat_at IS NULL OR sr.last_heartbeat_at < now() - interval '30 seconds' THEN 'offline'
		            ELSE wi.status END,
		       COALESCE(sr.node_key, ''), COALESCE(sr.host, ''), COALESCE(sr.udp_port, 0), COALESCE(sr.region, ''),
		       sr.last_heartbeat_at,
		       (SELECT COUNT(*) FROM world_sessions ws WHERE ws.instance_id = wi.id AND ws.session_state = 'active')::int,
		       (SELECT COUNT(*) FROM world_sessions ws WHERE ws.instance_id = wi.id AND ws.session_state IN ('connecting','saving'))::int,
		       wi.created_at, wi.updated_at
		FROM world_instances wi
		JOIN world_definitions wd ON wd.id = wi.world_id
		LEFT JOIN server_registry sr ON sr.id = wi.server_id
		WHERE wi.world_id = $1
		ORDER BY wi.created_at DESC
		LIMIT 500
	`, worldID)
	if err != nil {
		h.logger.Error("game admin world instances query failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()
	items := make([]adminWorldInstance, 0)
	for rows.Next() {
		var item adminWorldInstance
		var heartbeat sql.NullTime
		if err := rows.Scan(&item.ID, &item.InstanceKey, &item.Status, &item.EffectiveStatus, &item.NodeKey, &item.Host, &item.UDPPort, &item.Region, &heartbeat, &item.ActiveSessions, &item.PendingSessions, &item.CreatedAt, &item.UpdatedAt); err != nil {
			http.Error(w, "internal server error", http.StatusInternalServerError)
			return
		}
		if heartbeat.Valid { value := heartbeat.Time; item.LastHeartbeatAt = &value }
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		h.logger.Error("iterate game admin world instances failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "total": len(items), "limit": 500})
}

func (h *gamePlayerAdminHandlers) setWorldEnabled(w http.ResponseWriter, r *http.Request) {
	if !h.authorize(w, r) { return }
	worldID := strings.TrimSpace(r.PathValue("worldID"))
	if worldID == "" || len(worldID) > 64 { http.Error(w, "invalid world id", http.StatusBadRequest); return }
	var request struct { Enabled *bool `json:"enabled"` }
	if err := decodeJSON(w, r, &request); err != nil || request.Enabled == nil {
		http.Error(w, "enabled must be a boolean", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	tx, err := h.db.BeginTx(ctx, nil)
	if err != nil { http.Error(w, "internal server error", http.StatusInternalServerError); return }
	defer tx.Rollback()
	var current bool
	if err := tx.QueryRowContext(ctx, `SELECT enabled FROM world_definitions WHERE id = $1 FOR UPDATE`, worldID).Scan(&current); err != nil {
		if errors.Is(err, sql.ErrNoRows) { http.Error(w, "world not found", http.StatusNotFound); return }
		h.logger.Error("lock game admin world failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	if _, err := tx.ExecContext(ctx, `UPDATE world_definitions SET enabled = $2, updated_at = now() WHERE id = $1`, worldID, *request.Enabled); err != nil {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	var drainingInstances, requestedSessions, invalidatedTickets int64
	if !*request.Enabled {
		result, err := tx.ExecContext(ctx, `UPDATE world_instances SET status = 'draining', updated_at = now() WHERE world_id = $1 AND status <> 'offline'`, worldID)
		if err != nil { http.Error(w, "internal server error", http.StatusInternalServerError); return }
		drainingInstances, _ = result.RowsAffected()
		result, err = tx.ExecContext(ctx, `UPDATE world_sessions ws SET session_state = 'saving', updated_at = now() FROM characters c WHERE c.id = ws.character_id AND c.world_id = $1 AND ws.session_state = 'active'`, worldID)
		if err != nil { http.Error(w, "internal server error", http.StatusInternalServerError); return }
		requestedSessions, _ = result.RowsAffected()
		result, err = tx.ExecContext(ctx, `UPDATE world_entry_tickets t SET consumed_at = now() FROM characters c WHERE c.id = t.character_id AND c.world_id = $1 AND t.consumed_at IS NULL`, worldID)
		if err != nil { http.Error(w, "internal server error", http.StatusInternalServerError); return }
		invalidatedTickets, _ = result.RowsAffected()
	}
	if err := tx.Commit(); err != nil {
		h.logger.Error("commit game admin world state failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"world_id": worldID, "enabled": *request.Enabled, "previous_enabled": current, "draining_instances": drainingInstances, "requested_disconnects": requestedSessions, "invalidated_tickets": invalidatedTickets, "note": "启用世界后，实例需等待 WorldServer 下一次有效心跳恢复为 ready"})
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
	h := &gamePlayerAdminHandlers{db: db, apiKey: strings.TrimSpace(os.Getenv("GAME_ADMIN_INTERNAL_API_KEY")), logger: logger, entryService: worldentry.NewService(db), serverService: serverregistry.NewService(db)}
	mux.HandleFunc("GET /api/v1/internal/admin/worlds", h.listWorlds)
	mux.HandleFunc("GET /api/v1/internal/admin/worlds/{worldID}/instances", h.listWorldInstances)
	mux.HandleFunc("PATCH /api/v1/internal/admin/worlds/{worldID}/state", h.setWorldEnabled)
	mux.HandleFunc("GET /api/v1/internal/admin/servers/nodes", h.listServerNodes)
	mux.HandleFunc("PATCH /api/v1/internal/admin/servers/nodes/{nodeKey}/state", h.setServerNodeState)
	mux.HandleFunc("GET /api/v1/internal/admin/players/online", h.online)
	mux.HandleFunc("GET /api/v1/internal/admin/players/{accountID}", h.detail)
	mux.HandleFunc("POST /api/v1/internal/admin/players/{accountID}/disconnect", h.disconnect)
}
