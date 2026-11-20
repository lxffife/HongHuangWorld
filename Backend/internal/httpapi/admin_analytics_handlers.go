package httpapi

import (
 "context"
 "net/http"
 "time"
)

func (h *adminHandlers) analytics(w http.ResponseWriter, r *http.Request) {
 if _, ok := h.require(w, r, "dashboard.read"); !ok { return }
 now := time.Now().UTC()
 from := now.AddDate(0,0,-29)
 to := now.AddDate(0,0,1)
 if raw := r.URL.Query().Get("from"); raw != "" {
  parsed, err := time.Parse("2006-01-02", raw)
  if err != nil { http.Error(w, "from must be YYYY-MM-DD", http.StatusBadRequest); return }
  from = parsed.UTC()
 }
 if raw := r.URL.Query().Get("to"); raw != "" {
  parsed, err := time.Parse("2006-01-02", raw)
  if err != nil { http.Error(w, "to must be YYYY-MM-DD", http.StatusBadRequest); return }
  to = parsed.UTC().AddDate(0,0,1)
 }
 if !from.Before(to) || to.Sub(from) > 93*24*time.Hour { http.Error(w, "date range must be 1 to 93 days", http.StatusBadRequest); return }
 ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
 defer cancel()
 result, err := h.service.Analytics(ctx, from, to)
 if err != nil { h.logger.Error("admin analytics query failed", "error", err); http.Error(w, "internal server error", http.StatusInternalServerError); return }
 writeJSON(w, http.StatusOK, result)
}
