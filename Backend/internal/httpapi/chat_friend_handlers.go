package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

func (h *chatHandlers) listFriends(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	items, err := h.service.ListFriends(r.Context(), account.ID)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *chatHandlers) searchFriends(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := h.service.SearchCharacters(r.Context(), account.ID, r.URL.Query().Get("q"), limit)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *chatHandlers) incomingFriendRequests(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	items, err := h.service.ListIncomingFriendRequests(r.Context(), account.ID)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *chatHandlers) createFriendRequest(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	var req struct {
		CharacterID string `json:"character_id"`
		Message string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest); return
	}
	item, err := h.service.SendFriendRequest(r.Context(), account.ID, req.CharacterID, req.Message)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusCreated, map[string]any{"request": item})
}

func (h *chatHandlers) respondFriendRequest(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	requestID := strings.TrimSpace(r.PathValue("requestID"))
	accept := r.PathValue("decision") == "accept"
	if !accept && r.PathValue("decision") != "reject" {
		http.Error(w, "invalid friend request decision", http.StatusBadRequest); return
	}
	if err := h.service.RespondFriendRequest(r.Context(), account.ID, requestID, accept); err != nil {
		h.writeError(w, err); return
	}
	writeJSON(w, http.StatusOK, map[string]any{"accepted": accept})
}

func (h *chatHandlers) removeFriend(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	if err := h.service.RemoveFriend(r.Context(), account.ID, strings.TrimSpace(r.PathValue("characterID"))); err != nil {
		h.writeError(w, err); return
	}
	writeJSON(w, http.StatusOK, map[string]any{"removed": true})
}

func (h *chatHandlers) writeSocialError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, chat.ErrAlreadyFriend):
		http.Error(w, "already friends", http.StatusConflict)
	case errors.Is(err, chat.ErrFriendRequestExists):
		http.Error(w, "friend request already pending", http.StatusConflict)
	case errors.Is(err, chat.ErrFriendRequestNotFound):
		http.Error(w, "friend request not found", http.StatusNotFound)
	case errors.Is(err, chat.ErrFriendRequestsDisabled):
		http.Error(w, "recipient does not accept friend requests", http.StatusForbidden)
	case errors.Is(err, chat.ErrBlocked):
		http.Error(w, "friend action blocked", http.StatusForbidden)
	case errors.Is(err, chat.ErrFriendRequired):
		http.Error(w, "accepted friendship required", http.StatusForbidden)
	default:
		return false
	}
	return true
}

func (h *chatHandlers) conversationMessages(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := h.service.ListConversation(r.Context(), account.ID, strings.TrimSpace(r.PathValue("characterID")), strings.TrimSpace(r.URL.Query().Get("before")), limit)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "retention_days": 30})
}

func (h *chatHandlers) friendRequestPreference(w http.ResponseWriter, r *http.Request) {
	account, ok := h.authenticate(w, r)
	if !ok { return }
	if r.Method == http.MethodGet {
		allowed, err := h.service.GetAllowStrangerFriendRequests(r.Context(), account.ID)
		if err != nil { h.writeError(w, err); return }
		writeJSON(w, http.StatusOK, map[string]any{"allow_friend_requests": allowed})
		return
	}
	var req struct { Allow bool `json:"allow_friend_requests"` }
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest); return
	}
	if err := h.service.SetAllowStrangerFriendRequests(r.Context(), account.ID, req.Allow); err != nil {
		h.writeError(w, err); return
	}
	writeJSON(w, http.StatusOK, map[string]any{"allow_friend_requests": req.Allow})
}
