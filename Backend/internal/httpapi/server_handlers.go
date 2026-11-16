package httpapi

import (
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"

	"github.com/liflife/HongHuangWorld/Backend/internal/serverregistry"
)

type serverHandlers struct {
	service *serverregistry.Service
	apiKey  string
	logger  *slog.Logger
}

type serverHeartbeatRequest struct {
	NodeKey        string `json:"node_key"`
	Host           string `json:"host"`
	UDPPort        int    `json:"udp_port"`
	Region         string `json:"region"`
	Capacity       int    `json:"capacity"`
	CurrentPlayers int    `json:"current_players"`
	WorldID        string `json:"world_id"`
	InstanceKey    string `json:"instance_key"`
	Status         string `json:"status"`
}

func (h *serverHandlers) heartbeat(w http.ResponseWriter, r *http.Request) {
	if h.apiKey == "" {
		http.Error(w, "world server API is not configured", http.StatusServiceUnavailable)
		return
	}
	provided := r.Header.Get("X-World-Server-Key")
	if len(provided) != len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var request serverHeartbeatRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	result, err := h.service.Heartbeat(r.Context(), serverregistry.Heartbeat{
		NodeKey: request.NodeKey, Host: request.Host, UDPPort: request.UDPPort,
		Region: request.Region, Capacity: request.Capacity, CurrentPlayers: request.CurrentPlayers,
		WorldID: request.WorldID, InstanceKey: request.InstanceKey, Status: request.Status,
	})
	if err != nil {
		if errors.Is(err, serverregistry.ErrInvalidHeartbeat) {
			http.Error(w, "invalid server heartbeat fields or unavailable world", http.StatusBadRequest)
			return
		}
		h.logger.Error("server heartbeat failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, result)
}
