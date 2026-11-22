package httpapi

import (
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/character"
)

type spellMasteryHandlers struct {
	characterService *character.Service
	apiKey string
	logger *slog.Logger
}

func (h *spellMasteryHandlers) apply(w http.ResponseWriter, r *http.Request) {
	providedKey:=r.Header.Get("X-World-Server-Key")
	if h.apiKey=="" || len(providedKey)!=len(h.apiKey) || subtle.ConstantTimeCompare([]byte(providedKey),[]byte(h.apiKey))!=1 {
		http.Error(w,"unauthorized",http.StatusUnauthorized); return
	}
	nodeKey:=strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	var reward character.SpellMasteryReward
	if err:=decodeJSON(w,r,&reward);err!=nil { http.Error(w,"invalid request body",http.StatusBadRequest); return }
	result,err:=h.characterService.ApplySpellMasteryReward(r.Context(),nodeKey,reward)
	switch {
	case err==nil: writeJSON(w,http.StatusOK,result)
	case errors.Is(err,character.ErrInvalidSpellMasteryReward): http.Error(w,"invalid spell mastery payload",http.StatusBadRequest)
	case errors.Is(err,character.ErrRewardSession): http.Error(w,"character has no valid session on this server",http.StatusConflict)
	default: h.logger.Error("apply spell mastery reward failed","error",err); http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}
