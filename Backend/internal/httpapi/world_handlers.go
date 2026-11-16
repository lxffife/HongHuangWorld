package httpapi

import (
	"log/slog"
	"net/http"

	"github.com/liflife/HongHuangWorld/Backend/internal/world"
)

type worldHandlers struct {
	service *world.Service
	logger  *slog.Logger
}

func (h *worldHandlers) list(w http.ResponseWriter, r *http.Request) {
	items, err := h.service.ListEnabled(r.Context())
	if err != nil {
		h.logger.Error("list worlds failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}
