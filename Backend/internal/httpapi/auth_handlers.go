package httpapi

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
)

type authHandlers struct {
	service auth.Provider
	logger  *slog.Logger
}

type registerRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type authResponse struct {
	Account   auth.Account `json:"account"`
	Token     string       `json:"access_token"`
	TokenType string       `json:"token_type"`
	ExpiresAt time.Time    `json:"expires_at"`
}

func (h *authHandlers) register(w http.ResponseWriter, r *http.Request) {
	var request registerRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	account, token, expiresAt, err := h.service.Register(r.Context(), request.Username, request.Email, request.Password)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, authResponse{Account: account, Token: token, TokenType: "Bearer", ExpiresAt: expiresAt})
}

func (h *authHandlers) login(w http.ResponseWriter, r *http.Request) {
	var request loginRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	account, token, expiresAt, err := h.service.Login(r.Context(), request.Username, request.Password)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, authResponse{Account: account, Token: token, TokenType: "Bearer", ExpiresAt: expiresAt})
}

func (h *authHandlers) me(w http.ResponseWriter, r *http.Request) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	account, err := h.service.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	writeJSON(w, http.StatusOK, account)
}

func (h *authHandlers) writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrInvalidInput):
		http.Error(w, "username or password does not meet requirements", http.StatusBadRequest)
	case errors.Is(err, auth.ErrConflict):
		http.Error(w, "username or email already exists", http.StatusConflict)
	case errors.Is(err, auth.ErrInvalidCredentials), errors.Is(err, auth.ErrUnauthorized):
		http.Error(w, "invalid username or password", http.StatusUnauthorized)
	default:
		h.logger.Error("authentication request failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return errors.New("request must contain one JSON value")
	}
	return nil
}
