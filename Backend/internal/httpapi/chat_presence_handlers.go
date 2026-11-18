package httpapi

import (
	"net/http"
)

// presence reports the authenticated account's Chat connection state only.
// It intentionally does not expose Identity session state or Game world state.
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
