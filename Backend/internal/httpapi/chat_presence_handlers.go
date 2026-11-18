package httpapi

import (
	"net/http"
)

// presence reports the authenticated account's Chat connection state only.
func (h *chatHandlers) presence(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	status, err := h.service.GetChatPresence(r.Context(), account.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"chat_online": status.ChatOnline,
		"connections": status.Connections,
		"checked_at": status.CheckedAt,
		"presence_scope": "chat",
	})
}

func (h *chatHandlers) friendPresence(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	items, err := h.service.ListFriendPresence(r.Context(), account.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items": items,
		"presence_scope": "chat",
	})
}

// presenceSummary combines Chat leases with the asynchronous Game projection.
func (h *chatHandlers) presenceSummary(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	summary, err := h.service.GetPresenceSummary(r.Context(), account.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func (h *chatHandlers) friendPresenceSummary(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok {
		return
	}
	items, err := h.service.ListFriendPresenceSummary(r.Context(), account.ID)
	if err != nil {
		h.writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items": items,
		"presence_scope": "chat+game_projection",
	})
}
