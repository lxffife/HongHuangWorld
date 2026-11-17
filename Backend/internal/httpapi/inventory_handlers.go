package httpapi

import (
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/inventory"
)

type inventoryHandlers struct {
	authService *auth.Service
	service *inventory.Service
	apiKey string
	logger *slog.Logger
}

type createGroundDropRequest struct {
	DropID string `json:"drop_id"`
	SessionID string `json:"session_id"`
	CharacterID string `json:"character_id"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
}

type pickupGroundDropRequest struct {
	EventID string `json:"event_id"`
	DropID string `json:"drop_id"`
	SessionID string `json:"session_id"`
	CharacterID string `json:"character_id"`
}

func (h *inventoryHandlers) catalog(w http.ResponseWriter, r *http.Request) {
	items, err := h.service.ListItems(r.Context())
	if err != nil { h.logger.Error("list item catalog failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *inventoryHandlers) current(w http.ResponseWriter, r *http.Request) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") { http.Error(w, "unauthorized", http.StatusUnauthorized); return }
	account, err := h.authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil { http.Error(w, "unauthorized", http.StatusUnauthorized); return }
	items, err := h.service.CurrentInventory(r.Context(), account.ID)
	if err != nil { h.logger.Error("load current inventory failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}


func (h *inventoryHandlers) lootTable(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.authorizeServer(w, r); !ok { return }
	entries, err := h.service.ListLootTable(r.Context())
	if err != nil { h.logger.Error("list monster loot table failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError); return }
	writeJSON(w, http.StatusOK, map[string]any{"entries": entries})
}


func (h *inventoryHandlers) listDrops(w http.ResponseWriter, r *http.Request) {
	nodeKey, ok := h.authorizeServer(w, r); if !ok { return }
	drops, err := h.service.ListGroundDrops(r.Context(), nodeKey)
	if err != nil { h.logger.Error("list persisted ground drops failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError); return }
	writeJSON(w, http.StatusOK, map[string]any{"drops": drops})
}

func (h *inventoryHandlers) createDrop(w http.ResponseWriter, r *http.Request) {
	nodeKey, ok := h.authorizeServer(w, r); if !ok { return }
	var request createGroundDropRequest
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.service.CreateDrop(r.Context(), nodeKey, inventory.DropRequest{
		DropID: request.DropID, SessionID: request.SessionID, CharacterID: request.CharacterID,
		ItemID: request.ItemID, Quantity: request.Quantity, PositionX: request.PositionX, PositionZ: request.PositionZ,
	})
	switch {
	case err == nil: writeJSON(w, http.StatusCreated, result)
	case errors.Is(err, inventory.ErrInvalidRequest): http.Error(w, "invalid ground drop payload", http.StatusBadRequest)
	case errors.Is(err, inventory.ErrSessionInvalid): http.Error(w, "active character session not found on this server", http.StatusConflict)
	case errors.Is(err, inventory.ErrDropUnavailable): http.Error(w, "ground drop already exists", http.StatusConflict)
	default: h.logger.Error("create ground drop failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *inventoryHandlers) pickupDrop(w http.ResponseWriter, r *http.Request) {
	nodeKey, ok := h.authorizeServer(w, r); if !ok { return }
	var request pickupGroundDropRequest
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.service.PickupDrop(r.Context(), nodeKey, inventory.PickupRequest{
		EventID: request.EventID, DropID: request.DropID, SessionID: request.SessionID, CharacterID: request.CharacterID,
	})
	switch {
	case err == nil: writeJSON(w, http.StatusOK, result)
	case errors.Is(err, inventory.ErrInvalidRequest): http.Error(w, "invalid item pickup payload", http.StatusBadRequest)
	case errors.Is(err, inventory.ErrSessionInvalid): http.Error(w, "active character session not found on this server", http.StatusConflict)
	case errors.Is(err, inventory.ErrDropUnavailable): http.Error(w, "ground drop is unavailable", http.StatusConflict)
	case errors.Is(err, inventory.ErrInventoryFull): http.Error(w, "inventory stack is full", http.StatusConflict)
	default: h.logger.Error("pickup ground drop failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *inventoryHandlers) authorizeServer(w http.ResponseWriter, r *http.Request) (string, bool) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized); return "", false
	}
	nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	if nodeKey == "" { http.Error(w, "missing world server node", http.StatusBadRequest); return "", false }
	return nodeKey, true
}
