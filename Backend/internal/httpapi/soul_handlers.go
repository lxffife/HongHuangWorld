package httpapi

import (
	"errors"
	"crypto/subtle"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/soul"
)

type soulHandlers struct {
	authService auth.Provider
	soulService *soul.Service
	logger      *slog.Logger
	apiKey      string
}

type createSoulRequest struct {
	Name   string `json:"name"`
	Origin string `json:"origin"`
}

func (h *soulHandlers) create(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request createSoulRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	created, err := h.soulService.Create(r.Context(), account.ID, request.Name, request.Origin)
	if err != nil {
		switch {
		case errors.Is(err, soul.ErrInvalid):
			http.Error(w, "soul name or origin is invalid", http.StatusBadRequest)
		case errors.Is(err, soul.ErrConflict):
			http.Error(w, "account already has a soul", http.StatusConflict)
		default:
			h.logger.Error("create soul failed", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (h *soulHandlers) current(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	current, err := h.soulService.Current(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, soul.ErrNotFound) {
			http.Error(w, "soul not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current soul failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, current)
}

func (h *soulHandlers) currentAccount(w http.ResponseWriter, r *http.Request) (auth.Account, bool) {
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

 
func (h *soulHandlers) fate(w http.ResponseWriter, r *http.Request) {
 account, ok := h.currentAccount(w, r)
 if !ok { return }
 result, err := h.soulService.CurrentFate(r.Context(), account.ID)
 if err != nil {
  if errors.Is(err, soul.ErrNotFound) {
   http.Error(w, "soul not found", http.StatusNotFound)
   return
  }
  h.logger.Error("load soul fate failed", "error", err)
  http.Error(w, "internal server error", http.StatusInternalServerError)
  return
 }
 writeJSON(w, http.StatusOK, result)
}

func (h *soulHandlers) progression(w http.ResponseWriter, r *http.Request) {
 account, ok := h.currentAccount(w, r)
 if !ok { return }
 progression, err := h.soulService.CurrentProgression(r.Context(), account.ID)
 if err != nil {
  if errors.Is(err, soul.ErrNotFound) { http.Error(w, "soul progression not found", http.StatusNotFound); return }
  h.logger.Error("load soul progression failed", "error", err)
  http.Error(w, "internal server error", http.StatusInternalServerError)
  return
 }
 writeJSON(w, http.StatusOK, progression)
}

 
func (h *soulHandlers) applyReward(w http.ResponseWriter, r *http.Request) {
 providedKey := r.Header.Get("X-World-Server-Key")
 if h.apiKey == "" || len(providedKey) != len(h.apiKey) ||
  subtle.ConstantTimeCompare([]byte(providedKey), []byte(h.apiKey)) != 1 {
  http.Error(w, "unauthorized", http.StatusUnauthorized)
  return
 }
 nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
 var reward soul.Reward
 if err := decodeJSON(w, r, &reward); err != nil {
  http.Error(w, "invalid request body", http.StatusBadRequest)
  return
 }
 result, err := h.soulService.ApplyServerReward(r.Context(), nodeKey, reward)
 switch {
 case err == nil:
  writeJSON(w, http.StatusOK, result)
 case errors.Is(err, soul.ErrInvalidReward):
  http.Error(w, "invalid soul reward payload", http.StatusBadRequest)
 case errors.Is(err, soul.ErrRewardSession):
  http.Error(w, "soul reward session is not valid for this node", http.StatusConflict)
 default:
  h.logger.Error("apply soul reward failed", "error", err)
  http.Error(w, "internal server error", http.StatusInternalServerError)
 }
}

 
func (h *soulHandlers) breakthrough(w http.ResponseWriter, r *http.Request) {
 account, ok := h.currentAccount(w, r)
 if !ok { return }
 result, err := h.soulService.Breakthrough(r.Context(), account.ID)
 switch {
 case err == nil:
  writeJSON(w, http.StatusOK, result)
 case errors.Is(err, soul.ErrNotFound):
  http.Error(w, "soul not found", http.StatusNotFound)
 case errors.Is(err, soul.ErrInsufficientExperience):
  http.Error(w, "not enough soul experience for breakthrough", http.StatusConflict)
 case errors.Is(err, soul.ErrMaxRealm):
  http.Error(w, "soul has reached the highest configured realm", http.StatusConflict)
 default:
  h.logger.Error("soul breakthrough failed", "error", err)
  http.Error(w, "internal server error", http.StatusInternalServerError)
 }
}

 
func (h *soulHandlers) trials(w http.ResponseWriter, r *http.Request) {
 account, ok := h.currentAccount(w, r)
 if !ok { return }
 trials, err := h.soulService.Trials(r.Context(), account.ID)
 if err != nil {
  if errors.Is(err, soul.ErrNotFound) { http.Error(w, "soul not found", http.StatusNotFound); return }
  h.logger.Error("load soul trials failed", "error", err)
  http.Error(w, "internal server error", http.StatusInternalServerError)
  return
 }
 writeJSON(w, http.StatusOK, map[string]any{"trials":trials})
}

 
func (h *soulHandlers) reincarnationEligibility(w http.ResponseWriter,r *http.Request) {
 account,ok:=h.currentAccount(w,r); if !ok{return}
 result,err:=h.soulService.ReincarnationEligibility(r.Context(),account.ID)
 if err!=nil {
  if errors.Is(err,soul.ErrNotFound) { http.Error(w,"soul not found",http.StatusNotFound); return }
  h.logger.Error("load reincarnation eligibility failed","error",err)
  http.Error(w,"internal server error",http.StatusInternalServerError)
  return
 }
 writeJSON(w,http.StatusOK,result)
}


func (h *soulHandlers) essence(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	profile, err := h.soulService.CurrentEssence(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, soul.ErrNotFound) { http.Error(w, "soul essence not found", http.StatusNotFound); return }
		h.logger.Error("load soul essence failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, profile)
}


func (h *soulHandlers) applyAbsorption(w http.ResponseWriter, r *http.Request) {
 providedKey:=r.Header.Get("X-World-Server-Key")
 if h.apiKey=="" || len(providedKey)!=len(h.apiKey) ||
  subtle.ConstantTimeCompare([]byte(providedKey),[]byte(h.apiKey))!=1 {
  http.Error(w,"unauthorized",http.StatusUnauthorized); return
 }
 nodeKey:=strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
 var event soul.Absorption
 if err:=decodeJSON(w,r,&event);err!=nil {
  http.Error(w,"invalid request body",http.StatusBadRequest);return
 }
 result,err:=h.soulService.ApplyServerAbsorption(r.Context(),nodeKey,event)
 switch {
 case err==nil:
  writeJSON(w,http.StatusOK,result)
 case errors.Is(err,soul.ErrInvalidAbsorption):
  http.Error(w,"invalid soul absorption event",http.StatusBadRequest)
 case errors.Is(err,soul.ErrAbsorptionSession):
  http.Error(w,"soul absorption session is not valid for this node",http.StatusConflict)
 case errors.Is(err,soul.ErrAbsorptionCapacity):
  http.Error(w,"soul absorption capacity is full",http.StatusConflict)
 default:
  h.logger.Error("apply soul absorption failed","error",err)
  http.Error(w,"internal server error",http.StatusInternalServerError)
 }
}


func (h *soulHandlers) allocateRareEssence(w http.ResponseWriter, r *http.Request) {
 account,ok:=h.currentAccount(w,r);if !ok{return}
 var request struct {
  RecordID string `json:"record_id"`
  Attribute string `json:"attribute"`
 }
 if err:=decodeJSON(w,r,&request);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 attrs,err:=h.soulService.AllocateRareEssence(r.Context(),account.ID,request.RecordID,request.Attribute)
 switch {
 case err==nil: writeJSON(w,http.StatusOK,attrs)
 case errors.Is(err,soul.ErrInvalidAbsorption): http.Error(w,"invalid rare essence choice",http.StatusBadRequest)
 case errors.Is(err,soul.ErrAbsorptionChoiceUsed): http.Error(w,"rare essence was already allocated or is unavailable",http.StatusConflict)
 case errors.Is(err,soul.ErrNotFound): http.Error(w,"soul not found",http.StatusNotFound)
 default:
  h.logger.Error("allocate rare soul essence failed","error",err)
  http.Error(w,"internal server error",http.StatusInternalServerError)
 }
}


func (h *soulHandlers) fusions(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	recipes, err := h.soulService.FusionRecipes(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, soul.ErrNotFound) { http.Error(w, "soul not found", http.StatusNotFound); return }
		h.logger.Error("load soul fusion recipes failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"recipes": recipes})
}

func (h *soulHandlers) fuse(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	var request struct {
		RecipeID string `json:"recipe_id"`
	}
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	result, err := h.soulService.Fuse(r.Context(), account.ID, request.RecipeID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, soul.ErrNotFound):
		http.Error(w, "soul not found", http.StatusNotFound)
	case errors.Is(err, soul.ErrFusionUnavailable):
		http.Error(w, "fusion recipe or required soul mutations are unavailable", http.StatusConflict)
	case errors.Is(err, soul.ErrFusionCompleted):
		http.Error(w, "fusion recipe already completed", http.StatusConflict)
	default:
		h.logger.Error("fuse soul mutations failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}
