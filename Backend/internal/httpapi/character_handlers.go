package httpapi

import (
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/character"
)

type characterHandlers struct {
	authService      *auth.Service
	characterService *character.Service
	logger           *slog.Logger
}

type createCharacterRequest struct {
	Name    string `json:"name"`
	WorldID string `json:"world_id"`
	RaceID  string `json:"race_id"`
}

type reincarnateRequest struct {
	Name   string `json:"name"`
	RaceID string `json:"race_id"`
	RouteID string `json:"route_id"`
}

type allocateAttributePointsRequest struct {
	Attribute string `json:"attribute"`
	Points    int    `json:"points"`
}

// catalog is public game configuration; it contains no account-specific data.
func (h *characterHandlers) catalog(w http.ResponseWriter, r *http.Request) {
	catalog, err := h.characterService.CultivationCatalog(r.Context())
	if err != nil {
		h.logger.Error("load cultivation catalog failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"races": catalog})
}


func (h *characterHandlers) growthProfiles(w http.ResponseWriter, r *http.Request) {
	profiles, err := h.characterService.RaceGrowthCatalog(r.Context())
	if err != nil {
		h.logger.Error("load race growth profiles failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"profiles": profiles})
}

func (h *characterHandlers) bloodlines(w http.ResponseWriter, r *http.Request) {
	bloodlines, err := h.characterService.BloodlineCatalog(r.Context())
	if err != nil {
		h.logger.Error("load bloodline catalog failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"bloodlines": bloodlines})
}

func (h *characterHandlers) techniques(w http.ResponseWriter, r *http.Request) {
	techniques, err := h.characterService.TechniqueCatalog(r.Context())
	if err != nil {
		h.logger.Error("load technique catalog failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"techniques": techniques})
}

func (h *characterHandlers) createFirstLife(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request createCharacterRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	created, err := h.characterService.CreateFirstLife(r.Context(), account.ID, request.Name, request.WorldID, request.RaceID)
	if err != nil {
		switch {
		case errors.Is(err, character.ErrInvalid):
			http.Error(w, "character name or world id is invalid", http.StatusBadRequest)
		case errors.Is(err, character.ErrInvalidRace):
			http.Error(w, "unsupported race or cultivation system", http.StatusBadRequest)
		case errors.Is(err, character.ErrSoulRequired):
			http.Error(w, "create a soul profile first", http.StatusConflict)
		case errors.Is(err, character.ErrWorldInvalid):
			http.Error(w, "world is unavailable", http.StatusBadRequest)
		case errors.Is(err, character.ErrExists):
			http.Error(w, "first-life character already exists", http.StatusConflict)
		default:
			h.logger.Error("create first-life character failed", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusCreated, created)
}


func (h *characterHandlers) reincarnationPreview(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	preview, err := h.characterService.ReincarnationPreview(r.Context(), account.ID, r.URL.Query().Get("race_id"))
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, map[string]any{"inheritance": preview})
	case errors.Is(err, character.ErrInvalidRace):
		http.Error(w, "unsupported race", http.StatusBadRequest)
	case errors.Is(err, character.ErrSoulRequired):
		http.Error(w, "soul profile not found", http.StatusConflict)
	default:
		h.logger.Error("preview reincarnation inheritance failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *characterHandlers) reincarnationRoutes(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	routes, err := h.characterService.ReincarnationRoutes(r.Context(), account.ID)
	if err != nil {
		h.logger.Error("load reincarnation routes failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"routes": routes})
}

func (h *characterHandlers) reincarnate(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request reincarnateRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	created, err := h.characterService.Reincarnate(r.Context(), account.ID, request.Name, request.RaceID, request.RouteID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusCreated, created)
	case errors.Is(err, character.ErrInvalid):
		http.Error(w, "character name or race id is invalid", http.StatusBadRequest)
	case errors.Is(err, character.ErrInvalidRace):
		http.Error(w, "unsupported race or cultivation system", http.StatusBadRequest)
	case errors.Is(err, character.ErrInvalidBirthRoute):
		http.Error(w, "selected birth route is unavailable for this race or fate", http.StatusBadRequest)
	case errors.Is(err, character.ErrWorldInvalid):
		http.Error(w, "reincarnation destination is unavailable", http.StatusServiceUnavailable)
	case errors.Is(err, character.ErrReincarnationUnavailable):
		http.Error(w, "reincarnation requires a living current body with no active world session", http.StatusConflict)
	case errors.Is(err, character.ErrReincarnationRequirements):
		http.Error(w, "reincarnation requires 聚灵境 and completion of the Fengdu first soul trial", http.StatusConflict)
	default:
		h.logger.Error("reincarnate current soul failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *characterHandlers) allocateAttributePoints(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request allocateAttributePointsRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	err := h.characterService.AllocateAttributePoints(r.Context(), account.ID, request.Attribute, request.Points)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, map[string]any{"allocated": request.Points, "attribute": request.Attribute})
	case errors.Is(err, character.ErrInvalidAllocation):
		http.Error(w, "attribute must be strength, constitution, agility, spirit or vitality; points must be 1-100", http.StatusBadRequest)
	case errors.Is(err, character.ErrInsufficientPoints):
		http.Error(w, "not enough unspent attribute points", http.StatusConflict)
	case errors.Is(err, sql.ErrNoRows):
		http.Error(w, "living character not found", http.StatusNotFound)
	default:
		h.logger.Error("allocate character attribute points failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *characterHandlers) breakthrough(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	result, err := h.characterService.Breakthrough(r.Context(), account.ID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, character.ErrInsufficientCultivation):
		http.Error(w, "not enough cultivation for the next stage or realm", http.StatusConflict)
	case errors.Is(err, character.ErrMaxRealm):
		http.Error(w, "highest configured realm reached", http.StatusConflict)
	case errors.Is(err, sql.ErrNoRows):
		http.Error(w, "living character not found", http.StatusNotFound)
	default:
		h.logger.Error("character breakthrough failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *characterHandlers) currentStatus(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	status, err := h.characterService.CurrentStatus(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "character status not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current character status failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, status)
}

func (h *characterHandlers) history(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	items, err := h.characterService.History(r.Context(), account.ID)
	if err != nil {
		h.logger.Error("load soul life history failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *characterHandlers) memories(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	items, err := h.characterService.Memories(r.Context(), account.ID)
	if err != nil {
		h.logger.Error("load soul memories failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *characterHandlers) current(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	current, err := h.characterService.Current(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "character not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current character failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, current)
}

func (h *characterHandlers) currentAccount(w http.ResponseWriter, r *http.Request) (auth.Account, bool) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return auth.Account{}, false
	}
	account, err := h.authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return auth.Account{}, false
	}
	return account, true
}

type awakenBloodlineRequest struct { BloodlineID string `json:"bloodline_id"` }
type trainTechniqueRequest struct { TechniqueID string `json:"technique_id"`; Points int `json:"points"` }

func (h *characterHandlers) awakenBloodline(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r); if !ok { return }
	var request awakenBloodlineRequest
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.characterService.AwakenBloodline(r.Context(), account.ID, request.BloodlineID)
	switch {
	case err == nil: writeJSON(w, http.StatusOK, result)
	case errors.Is(err, character.ErrBloodlineNotOwned): http.Error(w, "bloodline not owned by current character", http.StatusNotFound)
	case errors.Is(err, character.ErrBloodlineMaxAwakening): http.Error(w, "bloodline has reached maximum awakening", http.StatusConflict)
	case errors.Is(err, character.ErrAwakeningRequirement): http.Error(w, "realm or cultivation requirement not met", http.StatusConflict)
	default: h.logger.Error("awaken bloodline failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *characterHandlers) trainTechnique(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r); if !ok { return }
	var request trainTechniqueRequest
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.characterService.TrainTechnique(r.Context(), account.ID, request.TechniqueID, request.Points)
	switch {
	case err == nil: writeJSON(w, http.StatusOK, result)
	case errors.Is(err, character.ErrInvalidTechniqueTraining): http.Error(w, "technique_id is required and points must be 1-100", http.StatusBadRequest)
	case errors.Is(err, character.ErrTechniqueNotOwned): http.Error(w, "technique not owned by current character", http.StatusNotFound)
	case errors.Is(err, character.ErrAwakeningRequirement): http.Error(w, "realm requirement not met", http.StatusConflict)
	case errors.Is(err, character.ErrInsufficientCultivation): http.Error(w, "not enough cultivation for technique training", http.StatusConflict)
	default: h.logger.Error("train technique failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}
